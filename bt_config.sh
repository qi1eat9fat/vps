#!/bin/bash

# 宝塔面板配置修改脚本（CentOS 7.6专用版）
# 用法: ./bt_config_centos.sh [选项]

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
    echo "宝塔面板配置修改脚本 (CentOS 7.6)"
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

# 检查并配置防火墙（CentOS 7.6专用）
configure_firewall() {
    local port=$1
    
    # 检查firewalld是否运行
    if systemctl is-active --quiet firewalld; then
        echo "检测到firewalld正在运行，配置端口放行..."
        
        # 检查端口是否已开放
        if firewall-cmd --list-ports | grep -q "$port/tcp"; then
            echo "端口 $port 已在firewalld中开放"
        else
            # 开放端口
            firewall-cmd --permanent --add-port=$port/tcp
            if [[ $? -eq 0 ]]; then
                firewall-cmd --reload
                echo "成功在firewalld中开放端口: $port"
            else
                echo "警告: 无法通过firewalld开放端口 $port"
            fi
        fi
    else
        echo "firewalld未运行，检查iptables..."
        
        # 检查iptables规则
        if iptables -L INPUT -n | grep -q "tcp dpt:$port"; then
            echo "端口 $port 已在iptables中开放"
        else
            # 添加iptables规则
            iptables -A INPUT -p tcp --dport $port -j ACCEPT
            if [[ $? -eq 0 ]]; then
                # 保存iptables规则（CentOS 7）
                if command -v iptables-save >/dev/null 2>&1; then
                    iptables-save > /etc/sysconfig/iptables
                    echo "成功在iptables中开放端口: $port"
                else
                    echo "警告: 端口 $port 已临时开放，但需要手动保存iptables规则"
                fi
            else
                echo "警告: 无法通过iptables开放端口 $port"
            fi
        fi
    fi
    
    # 额外检查SELinux
    if command -v getenforce >/dev/null 2>&1; then
        if [[ $(getenforce) != "Disabled" ]]; then
            echo "检测到SELinux启用，检查端口权限..."
            if ! semanage port -l | grep -q "http_port_t.*tcp.*$port"; then
                echo "正在为SELinux添加端口权限..."
                if command -v semanage >/dev/null 2>&1; then
                    semanage port -a -t http_port_t -p tcp $port
                    echo "SELinux端口权限已添加"
                else
                    echo "警告: 请安装policycoreutils-python-utils来管理SELinux端口"
                    echo "      或手动执行: semanage port -a -t http_port_t -p tcp $port"
                fi
            fi
        fi
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
        
        # 检查端口是否被占用（排除当前宝塔端口）
        CURRENT_PORT=$(cat "$CONFIG_FILE" 2>/dev/null || echo "$DEFAULT_PORT")
        if [[ "$PORT" != "$CURRENT_PORT" ]]; then
            if netstat -tuln | grep -q ":$PORT "; then
                echo "错误: 端口 $PORT 已被其他程序占用"
                exit 1
            fi
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
        
        # 配置防火墙
        configure_firewall "$PORT"
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
            echo "用户名和密码已修改"
        elif [[ ! -z "$USERNAME" ]]; then
            cd /www/server/panel && python tools.py username "$USERNAME"
            echo "用户名已修改为: $USERNAME"
        elif [[ ! -z "$PASSWORD" ]]; then
            # 获取当前用户名
            CURRENT_USER=$(cat /www/server/panel/data/default.pl 2>/dev/null || echo "admin")
            cd /www/server/panel && python tools.py panel "$CURRENT_USER" "$PASSWORD"
            echo "密码已修改"
        fi
    fi
}

# 重启宝塔服务
restart_bt_panel() {
    echo "正在重启宝塔面板服务..."
    
    # CentOS 7使用systemctl
    if systemctl is-active --quiet bt; then
        systemctl restart bt
    else
        /etc/init.d/bt restart
    fi
    
    if [[ $? -eq 0 ]]; then
        echo "宝塔面板服务重启成功"
        # 等待服务完全启动
        sleep 3
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
    echo "访问信息:"
    IP=$(curl -s ipv4.icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}' || echo "服务器IP")
    ENTRY=$(cat "$USER_FILE" 2>/dev/null || echo "$DEFAULT_SECURITY_ENTRY")
    PORT=$(cat "$CONFIG_FILE" 2>/dev/null || echo "$DEFAULT_PORT")
    echo "面板地址: https://$IP:$PORT$ENTRY"
    echo ""
    echo "防火墙状态:"
    if systemctl is-active --quiet firewalld; then
        echo "firewalld: 运行中"
        firewall-cmd --list-ports | grep -q "$PORT/tcp" && echo "端口 $PORT: 已开放" || echo "端口 $PORT: 未开放"
    else
        echo "firewalld: 未运行"
        if iptables -L INPUT -n | grep -q "tcp dpt:$PORT"; then
            echo "iptables端口 $PORT: 已开放"
        else
            echo "iptables端口 $PORT: 未开放"
        fi
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
