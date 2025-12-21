#!/bin/bash

# 配置文件路径
NFT_CONF="/etc/nftables.conf"
MAP_FILE="/etc/nft_mappings.conf"
UPDATE_SCRIPT="/usr/local/bin/nft_update_sync.sh"

# 检查状态颜色
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
    echo "     (1) 首次使用请先执行【安装环境】"
    echo "     (2) 支持单端口或端口段 (例如 1000-2000)"
    echo "     (3) 域名 IP 变动时，脚本会自动同步更新规则"
    echo " "
    echo "——————————————————"
    echo " 1. 安装环境 (nftables + 开启内核转发)"
    echo "——————————————————"
    echo " 2. 添加 转发规则 (支持域名/IP)"
    echo " 3. 查看 转发规则"
    echo " 4. 删除 转发规则"
    echo "——————————————————"
    echo " 5. 启动/重启 转发服务"
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

    # 创建基础 nftables 结构
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
    
    # 创建同步脚本
    create_sync_script
    
    systemctl enable nftables
    systemctl restart nftables
    echo -e "${GREEN}环境部署完成！${PLAIN}"
}

# 创建后台同步脚本
create_sync_script() {
    cat <<'EOF' > $UPDATE_SCRIPT
#!/bin/bash
MAP_FILE="/etc/nft_mappings.conf"
# 清空现有转发规则，重新构建
nft flush table ip nft_forward

while IFS="|" read -l_port r_domain r_port remark; do
    [[ -z "$l_port" ]] && continue
    
    # 解析域名 (如果是IP则直接返回)
    target_ip=$(dig +short "$r_domain" | grep -E '^[0-9.]+$' | head -n1)
    
    if [ ! -z "$target_ip" ]; then
        # 添加 DNAT
        nft add rule ip nft_forward prerouting tcp dport $l_port dnat to $target_ip:$r_port
        nft add rule ip nft_forward prerouting udp dport $l_port dnat to $target_ip:$r_port
        # 添加 SNAT (Masquerade) 确保回包
        nft add rule ip nft_forward postrouting ip daddr $target_ip masquerade
    fi
done < "$MAP_FILE"
EOF
    chmod +x $UPDATE_SCRIPT
    # 设置定时任务，每分钟检查一次 IP
    (crontab -l 2>/dev/null | grep -v "$UPDATE_SCRIPT"; echo "* * * * * $UPDATE_SCRIPT") | crontab -
}

# 添加转发
add_forward() {
    echo -e "${YELLOW}添加新转发规则：${PLAIN}"
    read -p "请输入本地监听端口 (如 10000 或 1000-2000): " l_port
    read -p "请输入目的地域名/IP: " r_domain
    read -p "请输入目的地端口 (如 20000): " r_port
    read -p "请输入备注: " remark
    
    echo "$l_port|$r_domain|$r_port|$remark" >> $MAP_FILE
    echo -e "${GREEN}添加成功，正在同步规则...${PLAIN}"
    $UPDATE_SCRIPT
}

# 查看转发
show_all_conf() {
    echo -e "\n${YELLOW}当前 nftables 转发规则：${PLAIN}"
    echo "--------------------------------------------------------------------------------"
    printf "%-5s | %-15s | %-25s | %-10s | %-15s\n" "序号" "本地端口" "目的地" "目标端口" "备注"
    echo "--------------------------------------------------------------------------------"
    local i=1
    while IFS="|" read l_port r_domain r_port remark; do
        [[ -z "$l_port" ]] && continue
        printf "%-5s | %-15s | %-25s | %-10s | %-15s\n" "$i" "$l_port" "$r_domain" "$r_port" "$remark"
        let i++
    done < "$MAP_FILE"
    echo "--------------------------------------------------------------------------------"
}

# 删除转发
delete_forward() {
    show_all_conf
    read -p "请输入要删除的规则序号: " del_num
    if [[ "$del_num" =~ ^[0-9]+$ ]]; then
        sed -i "${del_num}d" $MAP_FILE
        echo -e "${GREEN}删除成功，正在更新防火墙...${PLAIN}"
        $UPDATE_SCRIPT
    else
        echo -e "${RED}输入错误${PLAIN}"
    fi
}

# 卸载
uninstall_nft() {
    systemctl stop nftables
    systemctl disable nftables
    apt-get remove --purge -y nftables
    rm -f $MAP_FILE $UPDATE_SCRIPT
    sed -i "/$UPDATE_SCRIPT/d" /etc/crontab
    crontab -l | grep -v "$UPDATE_SCRIPT" | crontab -
    echo -e "${GREEN}卸载完成。${PLAIN}"
}

# 循环逻辑
while true; do
    show_menu
    read -p "请选择 [0-8]: " choice
    case $choice in
        1) deploy_env ;;
        2) add_forward ;;
        3) show_all_conf ;;
        4) delete_forward ;;
        5) $UPDATE_SCRIPT && systemctl restart nftables ;;
        6) systemctl stop nftables ;;
        8) uninstall_nft ;;
        0) exit 0 ;;
        *) echo "无效选项" ;;
    esac
    read -p "按回车键继续..." key
done
