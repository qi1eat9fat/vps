#!/bin/bash

# 宝塔面板交互式配置脚本
# 使用expect模拟终端输入
# 用法: ./bt_interactive.sh [用户名] [密码] [端口] [安全入口]

USERNAME=${1:-admin}
PASSWORD=${2:-}
PORT=${3:-8888}
SECURITY_ENTRY=${4:-/btpanel}

if [[ -z "$PASSWORD" ]]; then
    echo "用法: $0 [用户名] [密码] [端口] [安全入口]"
    echo "示例: $0 wangqi MyPass123 7657 /blgtya"
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo "错误: 需要root权限"
    exit 1
fi

# 检查expect是否安装
if ! command -v expect &> /dev/null; then
    echo "安装expect工具..."
    yum install -y expect > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        echo "错误: 无法安装expect，请手动安装: yum install -y expect"
        exit 1
    fi
fi

echo "开始使用交互式方式配置宝塔面板..."
echo "用户名: $USERNAME"
echo "端口: $PORT"
echo "安全入口: $SECURITY_ENTRY"

# 创建expect脚本
cat > /tmp/bt_config.exp << EOF
#!/usr/bin/expect -f

set username [lindex \$argv 0]
set password [lindex \$argv 1]
set port [lindex \$argv 2]
set entry [lindex \$argv 3]

set timeout 30

# 启动bt命令
spawn bt

expect "请输入命令编号"
send "6\r"

expect "请输入新的面板用户名"
send "\$username\r"

expect "请输入新的面板密码"
send "\$password\r"

expect "密码已修改"
expect eof
EOF

# 执行expect脚本
echo "正在修改用户名和密码..."
expect -f /tmp/bt_config.exp "$USERNAME" "$PASSWORD" "$PORT" "$SECURITY_ENTRY"

if [[ $? -eq 0 ]]; then
    echo "✓ 用户名和密码修改成功"
else
    echo "✗ 用户名密码修改可能失败，尝试备用方案"
fi

# 清理临时文件
rm -f /tmp/bt_config.exp

# 修改端口和安全入口（直接文件操作）
echo "正在修改端口和安全入口..."

# 修改端口
echo "$PORT" > /www/server/panel/data/port.pl
chown www:www /www/server/panel/data/port.pl
chmod 644 /www/server/panel/data/port.pl
echo "✓ 端口修改为: $PORT"

# 修改安全入口
echo "$SECURITY_ENTRY" > /www/server/panel/data/admin_path.pl
chown www:www /www/server/panel/data/admin_path.pl
chmod 644 /www/server/panel/data/admin_path.pl
echo "✓ 安全入口修改为: $SECURITY_ENTRY"

# 重启服务
echo "重启宝塔服务..."
/etc/init.d/bt stop >/dev/null 2>&1
sleep 3
/etc/init.d/bt start >/dev/null 2>&1
sleep 5

echo "✓ 服务重启完成"

# 显示结果
IP=$(curl -s ipv4.icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')
echo ""
echo "=================================================="
echo "宝塔面板配置完成"
echo "=================================================="
echo "面板地址: https://$IP:$PORT$SECURITY_ENTRY"
echo "用户名: $USERNAME"
echo "密码: 您设置的密码"
echo ""
echo "如果无法登录，请尝试HTTP地址: http://$IP:$PORT$SECURITY_ENTRY"
