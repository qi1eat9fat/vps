#!/bin/bash

# 宝塔面板配置修改脚本
# 用法: ./bt_config.sh [选项]

# 默认值
DEFAULT_SECURITY_ENTRY="/btpanel"
DEFAULT_USERNAME=""
DEFAULT_PASSWORD=""
DEFAULT_PORT="8888"
CONFIG_FILE="/www/server/panel/data/port.pl"
USER_FILE="/www/server/panel/data/admin_path.pl"
AUTH_FILE="/www/server/panel/data/userInfo.json"

# 显示帮助信息
show_help() {
    echo "宝塔面板配置修改脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -e, --entry      安全入口路径 (例如: /btpanel)"
    echo "  -u, --username   面板用户名"
    echo "  -p, --password   面板密码"
    echo "  -P, --port       面板端口 (默认: 8888)"
    echo "  -h, --help       显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 -e /myadmin -u newuser -p newpass123 -P 8889"
    echo "  $0 --entry /btpanel --username admin --password 123456 --port 8888"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "错误: 此脚本需要root权限运行" 
        exit 1
    fi
}

# 检查宝塔面板是否安装
check_bt_panel() {
    if [[ ! -f "/etc/init.d/bt" ]]; then
        echo "错误: 宝塔面板未安装或路径不正确"
        exit 1
    fi
}

# 验证参数
validate_params() {
    if [[ -z "$SECURITY_ENTRY" && -z "$USERNAME" && -z "$PASSWORD" && -z "$PORT" ]]; then
        echo "错误: 至少需要提供一个参数进行修改"
        show_help
        exit 1
    fi

    # 验证端口
    if [[ ! -z "$PORT" ]]; then
        if [[ ! "$PORT" =~ ^[0-9]+$ ]] || [[ "$PORT" -lt 1 ]] || [[ "$PORT" -gt 65535 ]]; then
            echo "错误: 端口号必须是1-65535之间的数字"
            exit 1
        fi
    fi

    # 验证安全入口
    if [[ ! -z "$SECURITY_ENTRY" ]]; then
        if [[ ! "$SECURITY_ENTRY" =~ ^/[a-zA-Z0-9_-]+$ ]]; then
            echo "错误: 安全入口必须以/开头，只能包含字母、数字、下划线和连字符"
            exit 1
        fi
    fi
}

# 修改端口
change_port() {
    if [[ ! -z "$PORT" ]]; then
        echo "正在修改面板端口为: $PORT"
        echo "$PORT" > "$CONFIG_FILE"
        
        # 检查防火墙设置
        if command -v ufw >/dev/null 2>&1; then
            ufw allow $PORT/tcp >/dev/null 2>&1
            echo "已开放UFW防火墙端口: $PORT"
        elif command -v firewall-cmd >/dev/null 2>&1; then
            firewall-cmd --permanent --add-port=$PORT/tcp >/dev/null 2>&1
            firewall-cmd --reload >/dev/null 2>&1
            echo "已开放FirewallD防火墙端口: $PORT"
        elif command -v iptables >/dev/null 2>&1; then
            iptables -A INPUT -p tcp --dport $PORT -j ACCEPT >/dev/null 2>&1
            echo "已开放iptables端口: $PORT"
        fi
    fi
}

# 修改安全入口
change_security_entry() {
    if [[ ! -z "$SECURITY_ENTRY" ]]; then
        echo "正在修改安全入口为: $SECURITY_ENTRY"
        echo "$SECURITY_ENTRY" > "$USER_FILE"
    fi
}

# 修改用户名和密码
change_credentials() {
    if [[ ! -z "$USERNAME" || ! -z "$PASSWORD" ]]; then
        echo "正在修改面板凭据..."
        
        # 使用宝塔命令行工具修改
        if [[ ! -z "$USERNAME" && ! -z "$PASSWORD" ]]; then
            cd /www/server/panel && python tools.py panel "$USERNAME" "$PASSWORD"
        elif [[ ! -z "$USERNAME" ]]; then
            cd /www/server/panel && python tools.py username "$USERNAME"
        elif [[ ! -z "$PASSWORD" ]]; then
            cd /www/server/panel && python tools.py panel "$PASSWORD"
        fi
    fi
}

# 重启宝塔服务
restart_bt_panel() {
    echo "正在重启宝塔面板服务..."
    /etc/init.d/bt restart >/dev/null 2>&1
    
    if [[ $? -eq 0 ]]; then
        echo "宝塔面板服务重启成功"
    else
        echo "警告: 宝塔面板服务重启失败，请手动检查"
    fi
}

# 显示修改结果
show_result() {
    echo ""
    echo "=" * 50
    echo "宝塔面板配置修改完成"
    echo "=" * 50
    
    if [[ ! -z "$PORT" ]]; then
        CURRENT_PORT=$(cat "$CONFIG_FILE" 2>/dev/null || echo "未知")
        echo "面板端口: $CURRENT_PORT"
    fi
    
    if [[ ! -z "$SECURITY_ENTRY" ]]; then
        CURRENT_ENTRY=$(cat "$USER_FILE" 2>/dev/null || echo "未知")
        echo "安全入口: $CURRENT_ENTRY"
    fi
    
    if [[ ! -z "$USERNAME" ]]; then
        echo "用户名: 已修改"
    fi
    
    if [[ ! -z "$PASSWORD" ]]; then
        echo "密码: 已修改"
    fi
    
    echo ""
    echo "访问地址:"
    if [[ ! -z "$PORT" || ! -z "$SECURITY_ENTRY" ]]; then
        IP=$(curl -s ipv4.icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}' || echo "服务器IP")
        ENTRY=$(cat "$USER_FILE" 2>/dev/null || echo "$DEFAULT_SECURITY_ENTRY")
        PORT=$(cat "$CONFIG_FILE" 2>/dev/null || echo "$DEFAULT_PORT")
        echo "http://$IP:$PORT$ENTRY"
    fi
    echo "=" * 50
}

# 主函数
main() {
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--entry)
                SECURITY_ENTRY="$2"
                shift 2
                ;;
            -u|--username)
                USERNAME="$2"
                shift 2
                ;;
            -p|--password)
                PASSWORD="$2"
                shift 2
                ;;
            -P|--port)
                PORT="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # 检查权限和安装
    check_root
    check_bt_panel
    
    # 验证参数
    validate_params
    
    # 执行修改操作
    change_port
    change_security_entry
    change_credentials
    restart_bt_panel
    show_result
}

# 如果直接运行脚本，则执行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
