#!/bin/bash

# 宝塔面板配置修改脚本（CentOS 7.6兼容版）
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
    echo "宝塔面板配置修改脚本 (CentOS 7.6兼容版)"
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

# 检查Python版本并创建兼容的修改脚本
create_python_script() {
    local username=$1
    local password=$2
    
    # 创建Python脚本文件
    cat > /tmp/bt_change_credentials.py << 'EOF'
#!/usr/bin/env python
# -*- coding: utf-8 -*-

import sys
import os
import json
import hashlib
import random
import string

sys.path.insert(0, '/www/server/panel')
os.chdir('/www/server/panel')

try:
    import public
    from BTPanel import session, cache
except ImportError:
    print("错误: 无法导入宝塔面板模块")
    sys.exit(1)

def change_username(new_username):
    """修改用户名"""
    try:
        if not new_username or len(new_username) < 3:
            print("错误: 用户名长度至少3位")
            return False
            
        # 读取当前配置
        auth_file = '/www/server/panel/data/userInfo.json'
        if os.path.exists(auth_file):
            with open(auth_file, 'r') as f:
                auth_data = json.load(f)
        else:
            auth_data = {}
        
        # 更新用户名
        auth_data['username'] = new_username
        
        # 保存配置
        with open(auth_file, 'w') as f:
            json.dump(auth_data, f)
        
        # 更新默认用户文件
        default_file = '/www/server/panel/data/default.pl'
        with open(default_file, 'w') as f:
            f.write(new_username)
        
        print("用户名修改成功")
        return True
        
    except Exception as e:
        print("修改用户名失败: " + str(e))
        return False

def change_password(username, new_password):
    """修改密码"""
    try:
        if not new_password or len(new_password) < 5:
            print("错误: 密码长度至少5位")
            return False
            
        # 生成盐值
        salt = ''.join(random.choice(string.ascii_letters + string.digits) for _ in range(12))
        
        # 计算密码哈希
        password_hash = hashlib.md5((new_password + salt).encode('utf-8')).hexdigest()
        
        # 读取当前配置
        auth_file = '/www/server/panel/data/userInfo.json'
        if os.path.exists(auth_file):
            with open(auth_file, 'r') as f:
                auth_data = json.load(f)
        else:
            auth_data = {}
        
        # 更新密码信息
        auth_data['password'] = password_hash
        auth_data['salt'] = salt
        
        # 保存配置
        with open(auth_file, 'w') as f:
            json.dump(auth_data, f)
        
        print("密码修改成功")
        return True
        
    except Exception as e:
        print("修改密码失败: " + str(e))
        return False

def change_both(username, password):
    """同时修改用户名和密码"""
    try:
        if not change_username(username):
            return False
        if not change_password(username, password):
            return False
        print("用户名和密码修改成功")
        return True
    except Exception as e:
        print("修改失败: " + str(e))
        return False

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("用法: python bt_change_credentials.py <username> <password>")
        print("       python bt_change_credentials.py username <new_username>")
        print("       python bt_change_credentials.py password <new_password>")
        sys.exit(1)
    
    action = sys.argv[1]
    
    if action == "username":
        change_username(sys.argv[2])
    elif action == "password":
        # 获取当前用户名
        try:
            with open('/www/server/panel/data/default.pl', 'r') as f:
                current_username = f.read().strip()
            change_password(current_username, sys.argv[2])
        except:
            change_password("admin", sys.argv[2])
    else:
        change_both(sys.argv[1], sys.argv[2])
EOF

    # 执行Python脚本
    if [[ ! -z "$username" && ! -z "$password" ]]; then
        python /tmp/bt_change_credentials.py "$username" "$password"
    elif [[ ! -z "$username" ]]; then
        python /tmp/bt_change_credentials.py username "$username"
    elif [[ ! -z "$password" ]]; then
        python /tmp/bt_change_credentials.py password "$password"
    fi
    
    # 清理临时文件
    rm -f /tmp/bt_change_credentials.py
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
    
    # 额外检查SELinux
    if command -v getenforce >/dev/null 2>&1; then
        if [[ $(getenforce) != "Disabled" ]]; then
            echo "检测到SELinux启用，检查端口权限..."
            if command -v semanage >/dev/null 2>&1; then
                if ! semanage port -l 2>/dev/null | grep -q "http_port_t.*tcp.*$port"; then
                    echo "正在为SELinux添加端口权限..."
                    semanage port -a -t http_port_t -p tcp $port >/dev/null 2>&1
                    if [[ $? -eq 0 ]]; then
                        echo "SELinux端口权限已添加"
                    else
                        echo "警告: 无法添加SELinux端口权限，请手动执行:"
                        echo "      semanage port -a -t http_port_t -p tcp $port"
                    fi
                fi
            else
                echo "提示: 要管理SELinux端口，请安装: yum install policycoreutils-python"
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

# 修改用户名和密码（使用兼容方法）
change_credentials() {
    if [[ ! -z "$USERNAME" || ! -z "$PASSWORD" ]]; then
        echo "正在修改面板凭据..."
        
        # 使用兼容的Python脚本修改
        create_python_script "$USERNAME" "$PASSWORD"
        
        # 同时尝试使用宝塔命令行工具（备用方法）
        if [[ ! -z "$USERNAME" && ! -z "$PASSWORD" ]]; then
            echo "使用备用方法修改凭据..."
            cd /www/server/panel && python -c "
import sys
sys.path.insert(0, '/www/server/panel')
import public
public.set_panel_username('$USERNAME')
public.set_panel_password('$PASSWORD')
print('备用方法执行完成')
" 2>/dev/null || echo "备用方法执行完成"
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
        sleep 5
    else
        echo "警告: 宝塔面板服务重启失败，请手动检查"
        echo "尝试使用备用方式重启..."
        /etc/init.d/bt restart
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
    echo "面板地址: http://$IP:$PORT$ENTRY"
    echo ""
    echo "防火墙状态:"
    if systemctl is-active --quiet firewalld; then
        echo "firewalld: 运行中"
        if firewall-cmd --list-ports 2>/dev/null | grep -q "$PORT/tcp"; then
            echo "端口 $PORT: 已开放"
        else
            echo "端口 $PORT: 未开放"
        fi
    else
        echo "firewalld: 未运行"
        if iptables -L INPUT -n 2>/dev/null | grep -q "tcp dpt:$PORT"; then
            echo "iptables端口 $PORT: 已开放"
        else
            echo "iptables端口 $PORT: 未开放"
        fi
    fi
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
    change_credentials
    restart_bt_panel
    show_result
}

# 如果直接运行脚本，则执行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
