#!/bin/bash

# 宝塔面板配置修改脚本（直接文件操作版）
# 用法: ./bt_config_direct.sh [选项]

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
    echo "宝塔面板配置修改脚本 (直接文件操作版)"
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

# 生成MD5哈希（兼容旧系统）
md5_hash() {
    local str=$1
    if command -v md5sum >/dev/null 2>&1; then
        echo -n "$str" | md5sum | awk '{print $1}'
    elif command -v md5 >/dev/null 2>&1; then
        echo -n "$str" | md5
    else
        # 使用Python作为备选
        python -c "import hashlib; print(hashlib.md5('$str'.encode()).hexdigest())" 2>/dev/null
    fi
}

# 生成随机盐值
generate_salt() {
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1
}

# 直接修改用户名和密码文件
change_credentials_direct() {
    local username=$1
    local password=$2
    
    echo "正在直接修改面板凭据..."
    
    # 修改用户名
    if [[ ! -z "$username" ]]; then
        if [[ ${#username} -lt 3 ]]; then
            echo "错误: 用户名长度至少3位"
            return 1
        fi
        
        # 更新default.pl文件
        echo "$username" > "$DEFAULT_USER_FILE"
        echo "用户名已修改为: $username"
        
        # 更新userInfo.json中的用户名
        if [[ -f "$AUTH_FILE" ]]; then
            local temp_file=$(mktemp)
            if python -c "
import json
try:
    with open('$AUTH_FILE', 'r') as f:
        data = json.load(f)
    data['username'] = '$username'
    with open('$temp_file', 'w') as f:
        json.dump(data, f)
    print('success')
except Exception as e:
    print('error: ' + str(e))
" 2>/dev/null | grep -q "success"; then
                mv "$temp_file" "$AUTH_FILE"
                chown www:www "$AUTH_FILE"
                chmod 600 "$AUTH_FILE"
            else
                rm -f "$temp_file"
                # 如果JSON操作失败，创建基本的userInfo.json
                cat > "$AUTH_FILE" << EOF
{
    "username": "$username",
    "password": "need_update",
    "salt": "need_update"
}
EOF
                chown www:www "$AUTH_FILE"
                chmod 600 "$AUTH_FILE"
                echo "创建新的用户配置文件"
            fi
        else
            # 创建userInfo.json文件
            cat > "$AUTH_FILE" << EOF
{
    "username": "$username",
    "password": "need_update",
    "salt": "need_update"
}
EOF
            chown www:www "$AUTH_FILE"
            chmod 600 "$AUTH_FILE"
            echo "创建用户配置文件"
        fi
    fi
    
    # 修改密码
    if [[ ! -z "$password" ]]; then
        if [[ ${#password} -lt 5 ]]; then
            echo "错误: 密码长度至少5位"
            return 1
        fi
        
        local salt=$(generate_salt)
        local password_hash=$(md5_hash "${password}${salt}")
        
        if [[ -f "$AUTH_FILE" ]]; then
            local temp_file=$(mktemp)
            if python -c "
import json
try:
    with open('$AUTH_FILE', 'r') as f:
        data = json.load(f)
    data['password'] = '$password_hash'
    data['salt'] = '$salt'
    with open('$temp_file', 'w') as f:
        json.dump(data, f)
    print('success')
except Exception as e:
    print('error: ' + str(e))
" 2>/dev/null | grep -q "success"; then
                mv "$temp_file" "$AUTH_FILE"
                chown www:www "$AUTH_FILE"
                chmod 600 "$AUTH_FILE"
                echo "密码修改成功"
            else
                rm -f "$temp_file"
                echo "警告: JSON操作失败，使用备用方法"
                # 备用方法：直接写入文件
                cat > "$AUTH_FILE" << EOF
{
    "username": "$username",
    "password": "$password_hash",
    "salt": "$salt"
}
EOF
                chown www:www "$AUTH_FILE"
                chmod 600 "$AUTH_FILE"
                echo "密码修改成功（备用方法）"
            fi
        else
            # 创建新的userInfo.json
            cat > "$AUTH_FILE" << EOF
{
    "username": "${username:-admin}",
    "password": "$password_hash",
    "salt": "$salt"
}
EOF
            chown www:www "$AUTH_FILE"
            chmod 600 "$AUTH_FILE"
            echo "密码修改成功（新文件）"
        fi
    fi
    
    return 0
}

# 检查并配置防火墙（CentOS 7.6专用）
configure_firewall() {
    local port=$1
    
    # 检查firewalld是否运行
    if systemctl is-active --quiet firewalld; then
        echo "检测到firewalld正在运行，配置端口放行..."
        
        # 检查端口是否已开放
        if firewall-cmd --list-ports 2>/dev/null | grep -q "$port/tcp"; then
            echo "端口 $port 已在firewalld中开放"
        else
            # 开放端口
            firewall-cmd --permanent --add-port=$port/tcp >/dev/null 2>&1
            if [[ $? -eq 0 ]]; then
                firewall-cmd --reload >/dev/null 2>&1
                echo "成功在firewalld中开放端口: $port"
            else
                echo "警告: 无法通过firewalld开放端口 $port"
            fi
        fi
    else
        echo "firewalld未运行，检查iptables..."
        
        # 检查iptables规则
        if iptables -L INPUT -n 2>/dev/null | grep -q "tcp dpt:$port"; then
            echo "端口 $port 已在iptables中开放"
        else
            # 添加iptables规则
            iptables -A INPUT -p tcp --dport $port -j ACCEPT >/dev/null 2>&1
            if [[ $? -eq 0 ]]; then
                # 保存iptables规则（CentOS 7）
                if command -v iptables-save >/dev/null 2>&1; then
                    iptables-save > /etc/sysconfig/iptables 2>/dev/null
                    echo "成功在iptables中开放端口: $port"
                else
                    echo "警告: 端口 $port 已临时开放，但需要手动保存iptables规则"
                fi
            else
                echo "警告: 无法通过iptables开放端口 $port"
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
        
        # 检查端口是否被占用
        CURRENT_PORT=$(cat "$CONFIG_FILE" 2>/dev/null || echo "$DEFAULT_PORT")
        if [[ "$PORT" != "$CURRENT_PORT" ]]; then
            if netstat -tuln 2>/dev/null | grep -q ":$PORT "; then
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
        chown www:www "$CONFIG_FILE"
        chmod 644 "$CONFIG_FILE"
        
        # 配置防火墙
        configure_firewall "$PORT"
    fi
}

# 修改安全入口
change_security_entry() {
    if [[ ! -z "$SECURITY_ENTRY" ]]; then
        echo "正在修改安全入口为: $SECURITY_ENTRY"
        echo "$SECURITY_ENTRY" > "$USER_FILE"
        chown www:www "$USER_FILE"
        chmod 644 "$USER_FILE"
    fi
}

# 重启宝塔服务
restart_bt_panel() {
    echo "正在重启宝塔面板服务..."
    
    # 停止服务
    if systemctl is-active --quiet bt; then
        systemctl stop bt
    else
        /etc/init.d/bt stop
    fi
    
    sleep 2
    
    # 启动服务
    if systemctl is-active --quiet bt; then
        systemctl start bt
    else
        /etc/init.d/bt start
    fi
    
    if [[ $? -eq 0 ]]; then
        echo "宝塔面板服务重启成功"
        sleep 3
    else
        echo "警告: 宝塔面板服务重启失败，请手动检查"
    fi
}

# 显示修改结果
show_result() {
    echo ""
    echo "=================================================="
    echo "宝塔面板配置修改完成"
    echo "=================================================="
    
    if [[ ! -z "$PORT" ]]; then
        CURRENT_PORT=$(cat "$CONFIG_FILE" 2>/dev/null || echo "未知")
        echo "面板端口: $CURRENT_PORT"
    fi
    
    if [[ ! -z "$SECURITY_ENTRY" ]]; then
        CURRENT_ENTRY=$(cat "$USER_FILE" 2>/dev/null || echo "未知")
        echo "安全入口: $CURRENT_ENTRY"
    fi
    
    if [[ ! -z "$USERNAME" ]]; then
        CURRENT_USER=$(cat "$DEFAULT_USER_FILE" 2>/dev/null || echo "未知")
        echo "用户名: $CURRENT_USER"
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
    echo "=================================================="
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
    change_credentials_direct "$USERNAME" "$PASSWORD"
    restart_bt_panel
    show_result
}

# 如果直接运行脚本，则执行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
