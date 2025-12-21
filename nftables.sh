#!/bin/bash

# 配置文件路径
NFT_CONF="/etc/nftables.conf"
MAP_FILE="/etc/nft_mappings.conf"
UPDATE_SCRIPT="/usr/local/bin/nft_update_sync.sh"

# 颜色定义
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
PLAIN="\033[0m"

# 检查安装状态
if command -v nft > /dev/null; then
    nft_status="已安装"
    nft_status_color=$GREEN
else
    nft_status="未安装"
    nft_status_color=$RED
fi

# 检查服务状态
check_service_status() {
    if systemctl is-active --quiet nftables; then
        echo -e "${GREEN}运行中${PLAIN}"
    else
        echo -e "${RED}未运行${PLAIN}"
    fi
}

# 显示菜单
show_menu() {
    clear
    echo "            欢迎使用 nftables 动态转发脚本"
    echo " ———————————— 内核级转发 | 支持动态域名 ————————————"
    echo "     修改内容：彻底修复 read 报错及同步逻辑"
    echo "     "
    echo "     (1) 首次使用请先执行【安装环境】"
    echo "     (2) 支持单端口 (如 80) 或端口段 (如 1000-2000)"
    echo "     (3) 每分钟自动检测域名 IP，变动即更新"
    echo " "
    echo "——————————————————"
    echo " 1. 安装环境 (nftables + 开启内核转发)"
    echo "——————————————————"
    echo " 2. 添加 转发规则"
    echo " 3. 查看 转发规则"
    echo " 4. 删除 转发规则"
    echo "——————————————————"
    echo " 5. 手动强制同步规则"
    echo " 6. 停止 转发服务"
    echo "——————————————————"
    echo " 8. 卸载 nftables 及脚本"
    echo "——————————————————"
    echo " 0. 退出脚本"
    echo "——————————————————"
    echo " "
    echo -e "软件状态：${nft_status_color}${nft_status}${PLAIN}"
    echo -n "运行状态："
    check_service_status
}

# 部署环境
deploy_env() {
    echo -e "${YELLOW}正在安装依赖并初始化...${PLAIN}"
    apt-get update && apt-get install -y nftables dnsutils cron
    
    # 开启内核转发
    sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    sysctl -p

    # 初始化 nftables 结构
    cat <<EOF > $NFT_CONF
flush ruleset
table ip nft_forward {
    chain prerouting {
        type nat hook prerouting priority -100;
    }
    chain postrouting {
        type nat hook postrouting priority 100;
    }
    chain forward {
        type filter hook forward priority 0;
        policy accept;
    }
}
EOF
    touch $MAP_FILE
    create_sync_script
    
    systemctl enable nftables
    systemctl restart nftables
    
    nft_status="已安装"
    nft_status_color=$GREEN
    echo -e "${GREEN}环境部署完成！${PLAIN}"
}

# 创建同步脚本 (已修正 read 参数)
create_sync_script() {
    cat <<'EOF' > $UPDATE_SCRIPT
#!/bin/bash
MAP_FILE="/etc/nft_mappings.conf"

# 确保表存在
nft add table ip nft_forward 2>/dev/null

# 清空并重建链，确保规则干净
nft flush table ip nft_forward
nft add chain ip nft_forward prerouting { type nat hook prerouting priority -100 \; }
nft add chain ip nft_forward postrouting { type nat hook postrouting priority 100 \; }
nft add chain ip nft_forward forward { type filter hook forward priority 0 \; policy accept \; }

# 修正后的 read 语句，去掉了错误的横杠
while IFS="|" read l_port r_domain r_port remark; do
    [[ -z "$l_port" ]] && continue
    
    # 解析 IP
    target_ip=$(dig +short "$r_domain" | grep -E '^[0-9.]+$' | head -n1)
    
    if [ ! -z "$target_ip" ]; then
        # 写入内核规则
        nft add rule ip nft_forward prerouting tcp dport $l_port dnat to $target_ip:$r_port
        nft add rule ip nft_forward prerouting udp dport $l_port dnat to $target_ip:$r_port
        nft add rule ip nft_forward postrouting ip daddr $target_ip masquerade
    fi
done < "$MAP_FILE"
EOF
    chmod +x $UPDATE_SCRIPT
    # 设置定时任务
    (crontab -l 2>/dev/null | grep -v "$UPDATE_SCRIPT"; echo "* * * * * $UPDATE_SCRIPT") | crontab -
}

# 添加规则
add_forward() {
    echo -e "${YELLOW}添加新转发：${PLAIN}"
    read -p "本地监听端口: " l_port
    read -p "目的地域名/IP: " r_domain
    read -p "目的地端口: " r_port
    read -p "备注: " remark
    
    if [[ -z "$l_port" || -z "$r_domain" || -z "$r_port" ]]; then
        echo -e "${RED}错误：必填项不能为空${PLAIN}"
        return
    fi

    echo "$l_port|$r_domain|$r_port|$remark" >> $MAP_FILE
    $UPDATE_SCRIPT
    echo -e "${GREEN}添加并同步成功！${PLAIN}"
}

# 查看规则
show_all_conf() {
    echo -e "\n${YELLOW}当前转发规则列表：${PLAIN}"
    echo "--------------------------------------------------------------------------------"
    printf "%-5s | %-15s | %-25s | %-10s | %-15s\n" "序号" "本地端口" "目的地" "目标端口" "备注"
    echo "--------------------------------------------------------------------------------"
    local i=1
    while IFS="|" read l_port r_domain r_port remark; do
        [[ -z "$l_port" ]] && continue
        printf "%-5s | %-15s | %-25s | %-10s | %-15s\n" "$i" "$l_port" "$r_domain" "$r_port" "$remark"
        let i++
    done < "$MAP_FILE"
}

# 删除规则
delete_forward() {
    show_all_conf
    read -p "请输入要删除的序号: " del_num
    if [[ "$del_num" =~ ^[0-9]+$ ]]; then
        sed -i "${del_num}d" $MAP_FILE
        $UPDATE_SCRIPT
        echo -e "${GREEN}删除成功${PLAIN}"
    else
        echo -e "${RED}输入无效${PLAIN}"
    fi
}

# 卸载
uninstall_nft() {
    read -p "确定卸载吗？(y/n): " confirm
    if [[ "$confirm" == "y" ]]; then
        systemctl stop nftables
        apt-get remove --purge -y nftables
        rm -f $MAP_FILE $UPDATE_SCRIPT
        crontab -l | grep -v "$UPDATE_SCRIPT" | crontab -
        echo -e "${GREEN}已彻底卸载${PLAIN}"
        nft_status="未安装"
        nft_status_color=$RED
    fi
}

# 循环菜单
while true; do
    show_menu
    read -p "请选择 [0-8]: " choice
    choice=$(echo $choice | tr -d '[:space:]')
    case $choice in
        1) deploy_env ;;
        2) add_forward ;;
        3) show_all_conf ;;
        4) delete_forward ;;
        5) $UPDATE_SCRIPT && echo -e "${GREEN}同步完成${PLAIN}" ;;
        6) systemctl stop nftables ;;
        8) uninstall_nft ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效选择${PLAIN}" ;;
    esac
    read -p "按回车继续..." key
done
