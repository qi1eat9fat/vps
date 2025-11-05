#!/bin/bash

# 脚本功能：修改 Debian 系统的主机名和时区
# 使用方法：sudo ./lxc_config.sh -h <新主机名> -t <时区>

set -e  # 遇到错误立即退出

# 显示使用说明
usage() {
    echo "用法: $0 -h <主机名> -t <时区>"
    echo "示例: $0 -h myserver -t Asia/Shanghai"
    echo "注意: 需要 root 权限运行"
    echo "支持的时区可以参考: /usr/share/zoneinfo/"
    exit 1
}

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "错误: 此脚本必须使用 root 权限运行" 
        exit 1
    fi
}

# 修改主机名
change_hostname() {
    local new_hostname=$1
    
    if [[ -z "$new_hostname" ]]; then
        echo "错误: 主机名不能为空"
        exit 1
    fi
    
    # 验证主机名格式（简单验证）
    if ! echo "$new_hostname" | grep -qE '^[a-zA-Z0-9-]{1,63}$'; then
        echo "错误: 主机名格式不正确"
        echo "主机名只能包含字母、数字和连字符，长度1-63字符"
        exit 1
    fi
    
    echo "正在修改主机名为: $new_hostname"
    
    # 临时修改当前会话的主机名
    hostnamectl set-hostname "$new_hostname"
    
    # 修改 /etc/hosts 文件
    if grep -q "127.0.1.1" /etc/hosts; then
        sed -i "s/127.0.1.1.*/127.0.1.1\t$new_hostname/" /etc/hosts
    else
        echo -e "127.0.1.1\t$new_hostname" >> /etc/hosts
    fi
    
    echo "主机名修改完成"
}

# 修改时区
change_timezone() {
    local timezone=$1
    
    if [[ -z "$timezone" ]]; then
        echo "错误: 时区不能为空"
        exit 1
    fi
    
    # 检查时区是否有效
    if [[ ! -f "/usr/share/zoneinfo/$timezone" ]]; then
        echo "错误: 时区 '$timezone' 无效或不存在"
        echo "请检查 /usr/share/zoneinfo/ 目录下的可用时区"
        exit 1
    fi
    
    echo "正在修改时区为: $timezone"
    
    # 创建时区链接
    ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime
    
    # 更新系统时区配置
    echo "$timezone" > /etc/timezone
    
    # 更新系统时钟
    dpkg-reconfigure -f noninteractive tzdata 2>/dev/null || true
    
    echo "时区修改完成"
}

# 显示当前配置
show_current_config() {
    echo "当前主机名: $(hostname)"
    echo "当前时区: $(cat /etc/timezone 2>/dev/null || timedatectl show --property=Timezone --value)"
}

# 主函数
main() {
    local new_hostname=""
    local new_timezone=""
    
    # 解析命令行参数
    while getopts "h:t:" opt; do
        case $opt in
            h)
                new_hostname="$OPTARG"
                ;;
            t)
                new_timezone="$OPTARG"
                ;;
            \?)
                echo "无效选项: -$OPTARG"
                usage
                ;;
            :)
                echo "选项 -$OPTARG 需要参数"
                usage
                ;;
        esac
    done
    
    # 检查是否提供了至少一个参数
    if [[ -z "$new_hostname" && -z "$new_timezone" ]]; then
        echo "当前系统配置:"
        show_current_config
        echo ""
        usage
    fi
    
    # 检查 root 权限
    check_root
    
    # 显示当前配置
    show_current_config
    echo ""
    
    # 修改主机名
    if [[ -n "$new_hostname" ]]; then
        change_hostname "$new_hostname"
        echo ""
    fi
    
    # 修改时区
    if [[ -n "$new_timezone" ]]; then
        change_timezone "$new_timezone"
        echo ""
    fi
    
    # 显示修改后的配置
    echo "修改后的系统配置:"
    show_current_config
    
    echo ""
    echo "配置修改完成！部分更改可能需要重启才能完全生效。"
}

# 运行主函数
main "$@"
