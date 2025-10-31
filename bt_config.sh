#!/bin/bash

# 宝塔面板配置修改脚本

# 默认值
DEFAULT_SECURITY_ENTRY="/btpanel"
DEFAULT_USERNAME=""
DEFAULT_PASSWORD=""
DEFAULT_PORT="8888"
CONFIG_FILE="/www/server/panel/data/port.pl"
USER_FILE="/www/server/panel/data/admin_path.pl"
AUTH_FILE="/www/server/panel/data/userInfo.json"
DEFAULT_USER_FILE="/www/server/panel/data/default.pl"

# 显示帮助信息
show_help() {
    echo "宝塔面板配置修改脚本"
    echo "适用于宝塔 11.2.0"
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

# 老版本宝塔的密码加密方式
old_version_password_hash() {
    local password=$1
    local salt=$2
    
    # 老版本可能使用不同的加密方式
    # 尝试多种可能的加密方式
    
    # 方式1: md5(md5(password) + salt)
    python -c "
import hashlib
password = '$password'
salt = '$salt'
hash1 = hashlib.md5(hashlib.md5(password.encode()).hexdigest().encode() + salt.encode()).hexdigest()
print(hash1)
" 2>/dev/null
}

# 直接修改配置文件（老版本兼容）
change_credentials_old_version() {
    local username=$1
    local password=$2
    
    echo "正在使用老版本兼容方式修改凭据..."
    
    # 修改用户名
    if [[ ! -z "$username" ]]; then
        if [[ ${#username} -lt 3 ]]; then
            echo "错误: 用户名长度至少3位"
            return 1
        fi
        
        echo "修改用户名: $username"
        echo "$username" > "$DEFAULT_USER_FILE"
        chown www:www "$DEFAULT_USER_FILE"
        chmod 600 "$DEFAULT_USER_FILE"
        echo "✓ 用户名修改完成"
    else
        # 如果没有提供新用户名，获取当前用户名
        if [[ -f "$DEFAULT_USER_FILE" ]]; then
            username=$(cat "$DEFAULT_USER_FILE" 2>/dev/null | head -n1)
        fi
        username=${username:-admin}
    fi
    
    # 修改密码
    if [[ ! -z "$password" ]]; then
        if [[ ${#password} -lt 5 ]]; then
            echo "错误: 密码长度至少5位"
            return 1
        fi
        
        echo "修改密码..."
        
        # 生成盐值
        salt=$(python -c "import string, random; print(''.join(random.choice(string.ascii_letters + string.digits) for _ in range(12)))" 2>/dev/null || echo "bt_salt_123")
        
        # 使用老版本加密方式
        password_hash=$(old_version_password_hash "$password" "$salt")
        
        if [[ -z "$password_hash" ]]; then
            # 如果加密失败，使用简单的md5(md5(password))作为备用
            password_hash=$(echo -n "$password" | md5sum | awk '{print $1}')
            password_hash=$(echo -n "$password_hash" | md5sum | awk '{print $1}')
            salt="old_version_salt"
            echo "⚠️ 使用备用加密方式"
        fi
        
        # 创建userInfo.json文件
        cat > "$AUTH_FILE" << EOF
{
    "username": "$username",
    "password": "$password_hash",
    "salt": "$salt"
}
EOF
        
        chown www:www "$AUTH_FILE"
        chmod 600 "$AUTH_FILE"
        echo "✓ 密码修改完成"
        
        # 尝试使用老版本宝塔的命令行工具
        echo "尝试使用老版本命令行工具..."
        cd /www/server/panel
        
        # 方法1: 使用panel命令
        python -c "
import sys
sys.path.insert(0, '/www/server/panel')
try:
    import public
    public.set_panel_username('$username')
    public.set_panel_password('$password')
    print('老版本工具执行成功')
except:
    print('老版本工具执行失败，但文件已直接修改')
" 2>/dev/null || true
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
            firewall-cmd --reload >/dev/null 2>&1
            echo "✓ 防火墙端口已开放"
        else
            echo "✓ 端口已在防火墙中开放"
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
    fi
}

# 修改安全入口
change_security_entry() {
    if [[ ! -z "$SECURITY_ENTRY" ]]; then
        echo "修改安全入口为: $SECURITY_ENTRY"
        echo "$SECURITY_ENTRY" > "$USER_FILE"
        chown www:www "$USER_FILE"
        chmod 644 "$USER_FILE"
    fi
}

# 重启宝塔服务
restart_bt_panel() {
    echo "重启宝塔面板服务..."
    
    /etc/init.d/bt stop >/dev/null 2>&1
    sleep 3
    /etc/init.d/bt start >/dev/null 2>&1
    sleep 5
    
    echo "✓ 服务重启完成"
}

# 显示修改结果
show_result() {
    echo ""
    echo "=================================================="
    echo "宝塔面板配置修改完成 (老版本兼容)"
    echo "=================================================="
    
    CURRENT_PORT=$(cat "$CONFIG_FILE" 2>/dev/null || echo "$DEFAULT_PORT")
    CURRENT_ENTRY=$(cat "$USER_FILE" 2>/dev/null || echo "$DEFAULT_SECURITY_ENTRY")
    CURRENT_USER=$(cat "$DEFAULT_USER_FILE" 2>/dev/null || echo "admin")
    
    echo "最终配置:"
    echo "▪ 面板端口: $CURRENT_PORT"
    echo "▪ 安全入口: $CURRENT_ENTRY"
    echo "▪ 用户名: $CURRENT_USER"
    if [[ ! -z "$PASSWORD" ]]; then
        echo "▪ 密码: 已修改"
    fi
    
    echo ""
    echo "面板访问地址:"
    IP=$(curl -s ipv4.icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')
    
    # 老版本可能不支持HTTPS，优先显示HTTPS，备用HTTP
    echo "🔒 HTTPS: https://$IP:$CURRENT_PORT$CURRENT_ENTRY"
    echo "🌐 HTTP: http://$IP:$CURRENT_PORT$CURRENT_ENTRY"
    
    echo ""
    echo "如果登录仍有问题，请尝试:"
    echo "1. 等待2分钟后重试"
    echo "2. 清除浏览器缓存"
    echo "3. 检查防火墙设置"
    echo ""
    echo "手动验证命令:"
    echo "cat $DEFAULT_USER_FILE # 查看用户名"
    echo "cat $AUTH_FILE # 查看密码配置"
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
    
    echo "开始修改宝塔面板配置 (兼容老版本)..."
    echo ""
    
    change_port
    change_security_entry
    change_credentials_old_version "$USERNAME" "$PASSWORD"
    restart_bt_panel
    show_result
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
