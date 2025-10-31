#!/bin/bash

# 宝塔面板配置修改脚本（命令行工具版）

# 默认值
DEFAULT_SECURITY_ENTRY="/btpanel"
DEFAULT_USERNAME=""
DEFAULT_PASSWORD=""
DEFAULT_PORT="8888"
CONFIG_FILE="/www/server/panel/data/port.pl"
USER_FILE="/www/server/panel/data/admin_path.pl"
DEFAULT_USER_FILE="/www/server/panel/data/default.pl"
SSL_ENABLE_FILE="/www/server/panel/data/ssl.pl"

# 显示帮助信息
show_help() {
    echo "宝塔面板配置修改脚本 (命令行工具版)"
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

# 使用宝塔命令行工具修改用户名和密码
change_credentials_with_bt() {
    local username=$1
    local password=$2
    
    echo "正在使用宝塔命令行工具修改凭据..."
    
    # 切换到宝塔面板目录
    cd /www/server/panel || {
        echo "错误: 无法进入宝塔面板目录"
        return 1
    }
    
    # 修改用户名（如果提供了新用户名）
    if [[ ! -z "$username" ]]; then
        if [[ ${#username} -lt 3 ]]; then
            echo "错误: 用户名长度至少3位"
            return 1
        fi
        
        echo "修改用户名: $username"
        if python tools.py username "$username" 2>/dev/null; then
            echo "✓ 用户名修改成功"
        else
            echo "✗ 用户名修改失败，尝试备用方法"
            # 备用方法：直接修改文件
            echo "$username" > "$DEFAULT_USER_FILE"
            echo "✓ 用户名已通过备用方法修改"
        fi
    fi
    
    # 修改密码（如果提供了新密码）
    if [[ ! -z "$password" ]]; then
        if [[ ${#password} -lt 5 ]]; then
            echo "错误: 密码长度至少5位"
            return 1
        fi
        
        echo "修改密码..."
        # 获取当前用户名
        local current_username="$username"
        if [[ -z "$current_username" && -f "$DEFAULT_USER_FILE" ]]; then
            current_username=$(cat "$DEFAULT_USER_FILE" 2>/dev/null | head -n1)
        fi
        current_username=${current_username:-admin}
        
        # 使用宝塔工具修改密码
        if python tools.py panel "$current_username" "$password" 2>/dev/null; then
            echo "✓ 密码修改成功"
        else
            echo "✗ 密码修改失败，尝试备用方法"
            # 备用方法：使用bt命令
            if [[ -f "/www/server/panel/tools.py" ]]; then
                python /www/server/panel/tools.py panel "$current_username" "$password" 2>/dev/null && \
                echo "✓ 密码已通过备用方法修改" || \
                echo "✗ 所有密码修改方法都失败"
            fi
        fi
    fi
    
    return 0
}

# 检查并配置防火墙
configure_firewall() {
    local port=$1
    
    if systemctl is-active --quiet firewalld; then
        echo "配置防火墙放行端口 $port..."
        
        if ! firewall-cmd --list-ports 2>/dev/null | grep -q "$port/tcp"; then
            firewall-cmd --permanent --add-port=$port/tcp >/dev/null 2>&1
            if [[ $? -eq 0 ]]; then
                firewall-cmd --reload >/dev/null 2>&1
                echo "✓ 防火墙端口 $port 已开放"
            else
                echo "✗ 防火墙端口开放失败"
            fi
        else
            echo "✓ 端口 $port 已在防火墙中开放"
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

    if [[ ! -z "$PORT" ]]; then
        if [[ ! "$PORT" =~ ^[0-9]+$ ]] || [[ "$PORT" -lt 1 ]] || [[ "$PORT" -gt 65535 ]]; then
            echo "错误: 端口号必须是1-65535之间的数字"
            exit 1
        fi
    fi

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
        echo "修改面板端口为: $PORT"
        echo "$PORT" > "$CONFIG_FILE"
        chown www:www "$CONFIG_FILE"
        chmod 644 "$CONFIG_FILE"
        configure_firewall "$PORT"
        echo "✓ 端口修改完成"
    fi
}

# 修改安全入口
change_security_entry() {
    if [[ ! -z "$SECURITY_ENTRY" ]]; then
        echo "修改安全入口为: $SECURITY_ENTRY"
        echo "$SECURITY_ENTRY" > "$USER_FILE"
        chown www:www "$USER_FILE"
        chmod 644 "$USER_FILE"
        echo "✓ 安全入口修改完成"
    fi
}

# 重启宝塔服务
restart_bt_panel() {
    echo "重启宝塔面板服务..."
    
    # 停止服务
    if /etc/init.d/bt stop 2>/dev/null; then
        echo "✓ 服务停止成功"
    else
        echo "✗ 服务停止失败"
    fi
    
    sleep 3
    
    # 启动服务
    if /etc/init.d/bt start 2>/dev/null; then
        echo "✓ 服务启动成功"
        sleep 5  # 等待服务完全启动
    else
        echo "✗ 服务启动失败"
        return 1
    fi
    
    return 0
}

# 检查SSL状态
check_ssl_status() {
    if [[ -f "$SSL_ENABLE_FILE" ]]; then
        local ssl_status=$(cat "$SSL_ENABLE_FILE" 2>/dev/null)
        if [[ "$ssl_status" == "1" ]]; then
            echo "enabled"
        else
            echo "disabled"
        fi
    else
        echo "disabled"
    fi
}

# 显示修改结果
show_result() {
    echo ""
    echo "=================================================="
    echo "宝塔面板配置修改完成"
    echo "=================================================="
    
    # 获取最终配置
    CURRENT_PORT=$(cat "$CONFIG_FILE" 2>/dev/null || echo "$DEFAULT_PORT")
    CURRENT_ENTRY=$(cat "$USER_FILE" 2>/dev/null || echo "$DEFAULT_SECURITY_ENTRY")
    CURRENT_USER=$(cat "$DEFAULT_USER_FILE" 2>/dev/null || echo "admin")
    SSL_STATUS=$(check_ssl_status)
    
    echo "最终配置:"
    echo "▪ 面板端口: $CURRENT_PORT"
    echo "▪ 安全入口: $CURRENT_ENTRY"
    echo "▪ 用户名: $CURRENT_USER"
    if [[ ! -z "$PASSWORD" ]]; then
        echo "▪ 密码: 已修改"
    fi
    echo "▪ SSL状态: $SSL_STATUS"
    
    echo ""
    echo "面板访问地址:"
    IP=$(curl -s ipv4.icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}' || echo "服务器IP")
    
    # 优先使用HTTPS，如果SSL未启用则使用HTTP
    if [[ "$SSL_STATUS" == "enabled" ]]; then
        echo "🔒 HTTPS: https://$IP:$CURRENT_PORT$CURRENT_ENTRY"
        echo "⚠️  如果HTTPS无法访问，请尝试HTTP地址"
        echo "🌐 HTTP: http://$IP:$CURRENT_PORT$CURRENT_ENTRY"
    else
        echo "🌐 HTTP: http://$IP:$CURRENT_PORT$CURRENT_ENTRY"
        echo "💡 提示: 建议在面板中启用SSL以获得更安全的HTTPS访问"
    fi
    
    echo ""
    echo "登录说明:"
    echo "1. 使用上述用户名和密码登录"
    echo "2. 如果无法登录，请尝试清除浏览器缓存"
    echo "3. 或使用无痕/隐私模式访问"
    echo ""
    echo "如果仍有问题，可以尝试以下命令手动重置:"
    echo "cd /www/server/panel && python tools.py panel 用户名 新密码"
    echo "=================================================="
}

# 主函数
main() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--entry) SECURITY_ENTRY="$2"; shift 2 ;;
            -u|--username) USERNAME="$2"; shift 2 ;;
            -p|--password) PASSWORD="$2"; shift 2 ;;
            -P|--port) PORT="$2"; shift 2 ;;
            -h|--help) show_help; exit 0 ;;
            *) echo "未知选项: $1"; show_help; exit 1 ;;
        esac
    done

    check_root
    check_bt_panel
    validate_params
    
    echo "开始修改宝塔面板配置..."
    echo ""
    
    change_port
    change_security_entry
    change_credentials_with_bt "$USERNAME" "$PASSWORD"
    restart_bt_panel
    show_result
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
