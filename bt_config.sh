#!/bin/bash

# 设置新的参数
NEW_USERNAME="${1:-new_admin}"
NEW_PASSWORD="${2:-new_password123}"
NEW_PORT="${3:-8888}"
NEW_ENTRY="${4:-new_entry}"

# 检查并安装expect工具
echo "检查expect是否已安装..."
if ! command -v expect &> /dev/null; then
    echo "正在安装expect工具..."
    yum install -y expect
    if [ $? -eq 0 ]; then
        echo "expect安装成功"
    else
        echo "expect安装失败，请检查网络或yum配置"
        exit 1
    fi
else
    echo "expect已安装"
fi

# 使用expect工具实现自动交互
expect << EOF
spawn bt
expect "请输入命令编号"
send "6\r"
expect "请输入新的面板用户名"
send "$NEW_USERNAME\r"
expect eof

spawn bt
expect "请输入命令编号"
send "5\r"
expect "请输入新的面板密码"
send "$NEW_PASSWORD\r"
expect eof

spawn bt
expect "请输入命令编号"
send "8\r"
expect "请输入新的面板端口"
send "$NEW_PORT\r"
expect eof

spawn bt
expect "请输入命令编号"
send "28\r"
expect "请输入新的安全入口名称"
send "$NEW_ENTRY\r"
expect eof
EOF

# 重启面板服务
/etc/init.d/bt restart
