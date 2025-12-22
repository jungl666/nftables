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

# 内部函数：检查同步脚本是否存在
check_env_installed() {
    if [ ! -f "$UPDATE_SCRIPT" ]; then
        echo -e "${RED}错误：检测到同步脚本不存在！${PLAIN}"
        echo -e "${YELLOW}请先选择 1 安装环境。${PLAIN}"
        return 1
    fi
    return 0
}

# 显示菜单
show_menu() {
    clear
    echo "            欢迎使用 nftables 动态转发脚本"
    echo " ———————————— 内核级转发 | 支持动态域名 ————————————"
    echo "      修改内容：增加安装前置检查，修复报错逻辑"
    echo "      "
    echo "      (1) 首次使用请先执行【安装环境】"
    echo "      (2) 支持单端口 (如 80) 或端口段 (如 1000-2000)"
    echo "      (3) 每分钟自动检测域名 IP，变动即更新"
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
    echo  "软件状态："
    echo  "运行状态："
    check_service_status
}

# 部署环境
deploy_env() {
    echo  "正在安装依赖并初始化..."
    apt-get update && apt-get install  nftables dnsutils cron
    
    # 开启内核转发
    sed   /etc/sysctl.conf
    echo  >> /etc/sysctl.conf
    sysctl 

    # 初始化 nftables 结构
    cat 




    }


    }



    }
}



    


    


    echo  "环境部署完成！"
}

# 创建同步脚本





# 确保表存在


# 清空并重建链







    

    








    # 设置定时任务

}

# 添加规则


    
    echo  "添加新转发："




    

        echo  "错误：必填项不能为空"




    

        echo -e "${GREEN}添加并同步成功！${PLAIN}"

        echo -e "${RED}规则已记录，但执行同步失败，请检查 nftables 状态！${PLAIN}"

}

# 查看规则


        echo -e "${RED}规则文件不存在${PLAIN}"


    echo -e "\n${YELLOW}当前转发规则列表：${PLAIN}"









}

# 删除规则



    read -p "请输入要删除的序号: " del_num



        echo -e "${GREEN}删除成功并已更新内核规则${PLAIN}"

        echo -e "${RED}输入无效${PLAIN}"

}

# 卸载







        echo -e "${GREEN}已彻底卸载${PLAIN}"



}

# 循环菜单









        5) check_env_installed && $UPDATE_SCRIPT && echo -e "${GREEN}同步完成${PLAIN}" ;;



        *) echo -e "${RED}无效选择${PLAIN}" ;;


