#!/bin/bash

# 完整系统配置脚本
# 功能：通过命令行参数设置hostname和SSH公钥

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认值（可选）
DEFAULT_HOSTNAME="qi"
DEFAULT_SSH_KEY=""

# 变量
NEW_HOSTNAME=""
SSH_PUBLIC_KEY=""

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# 显示用法
show_usage() {
    cat << EOF
用法: $0 [选项]

选项:
    -h, --hostname HOSTNAME    设置新的hostname（必需）
    -k, --key SSH_PUBLIC_KEY   设置SSH公钥（必需）
    -f, --key-file FILE        从文件读取SSH公钥
    --help                     显示此帮助信息

示例:
    $0 -h qi -k "ssh-rsa AAAAB3NzaC1yc2E..."
    $0 --hostname myserver --key-file /path/to/public_key.pub
    $0 -h qi -f ~/.ssh/id_rsa.pub

注意:
    - 必须提供hostname和SSH公钥（直接或通过文件）
    - 脚本需要root权限运行
    - 请确保在另一个终端测试密钥登录后再继续

EOF
}

# 解析命令行参数
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--hostname)
                NEW_HOSTNAME="$2"
                shift 2
                ;;
            -k|--key)
                SSH_PUBLIC_KEY="$2"
                shift 2
                ;;
            -f|--key-file)
                if [[ -f "$2" ]]; then
                    SSH_PUBLIC_KEY=$(cat "$2")
                    log_info "从文件读取公钥: $2"
                else
                    log_error "公钥文件不存在: $2"
                    exit 1
                fi
                shift 2
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# 验证参数
validate_arguments() {
    local valid=true
    
    # 检查hostname
    if [[ -z "$NEW_HOSTNAME" ]]; then
        log_error "必须提供hostname参数"
        valid=false
    else
        # 简单的hostname验证
        if ! [[ "$NEW_HOSTNAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]$ ]]; then
            log_error "无效的hostname格式: $NEW_HOSTNAME"
            log_error "hostname只能包含字母、数字和连字符，不能以连字符开头或结尾"
            valid=false
        fi
    fi
    
    # 检查SSH公钥
    if [[ -z "$SSH_PUBLIC_KEY" ]]; then
        log_error "必须提供SSH公钥参数"
        valid=false
    else
        # 简单的SSH公钥验证
        if ! [[ "$SSH_PUBLIC_KEY" =~ ^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp) ]]; then
            log_error "无效的SSH公钥格式"
            log_error "公钥应以 'ssh-rsa', 'ssh-ed25519' 或 'ecdsa-sha2-nistp' 开头"
            valid=false
        fi
    fi
    
    if [[ $valid != true ]]; then
        show_usage
        exit 1
    fi
}

# 检查是否以root权限运行
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_info "以root权限运行"
    else
        log_error "请使用sudo或以root用户运行此脚本"
        exit 1
    fi
}

# 显示配置预览
show_preview() {
    log_info "=== 配置预览 ==="
    echo "Hostname: $NEW_HOSTNAME"
    echo "SSH公钥类型: $(echo "$SSH_PUBLIC_KEY" | cut -d' ' -f1)"
    echo "SSH公钥指纹: $(echo "$SSH_PUBLIC_KEY" | cut -d' ' -f2 | base64 -d 2>/dev/null | md5sum | cut -d' ' -f1 2>/dev/null || echo "无法计算")"
    echo ""
}

# 设置hostname
set_hostname() {
    local current_hostname=$(hostname)
    
    if [[ "$current_hostname" == "$NEW_HOSTNAME" ]]; then
        log_info "hostname已经是 '$NEW_HOSTNAME'，无需修改"
        return 0
    fi
    
    log_info "设置hostname: $current_hostname → $NEW_HOSTNAME"
    
    if hostnamectl set-hostname "$NEW_HOSTNAME"; then
        log_info "hostname设置成功"
        
        # 更新当前shell的hostname显示
        if [[ -n "$BASH" ]]; then
            export HOSTNAME="$NEW_HOSTNAME"
            PS1="\\u@$NEW_HOSTNAME \\W\\$ "
        fi
    else
        log_error "hostname设置失败"
        exit 1
    fi
}

# 配置用户SSH密钥
setup_ssh_keys() {
    local current_user=$(logname 2>/dev/null || echo "${SUDO_USER:-$USER}")
    local user_home=$(eval echo "~$current_user")
    local ssh_dir="$user_home/.ssh"
    local auth_file="$ssh_dir/authorized_keys"
    
    log_info "为用户 $current_user 配置SSH密钥..."
    
    # 创建.ssh目录
    if [[ ! -d "$ssh_dir" ]]; then
        mkdir -p "$ssh_dir"
        log_info "创建目录: $ssh_dir"
    fi
    
    # 备份现有的authorized_keys（如果存在）
    if [[ -f "$auth_file" ]]; then
        local backup_file="$auth_file.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$auth_file" "$backup_file"
        log_info "备份现有密钥文件: $backup_file"
    fi
    
    # 添加公钥到authorized_keys
    if ! grep -q "$SSH_PUBLIC_KEY" "$auth_file" 2>/dev/null; then
        echo "$SSH_PUBLIC_KEY" >> "$auth_file"
        log_info "公钥已添加到: $auth_file"
    else
        log_warn "公钥已存在，跳过添加"
    fi
    
    # 设置正确的权限
    chmod 700 "$ssh_dir"
    chmod 600 "$auth_file"
    chown -R "$current_user:$current_user" "$ssh_dir"
    
    log_info "SSH密钥配置完成"
}

# 备份SSH配置文件
backup_ssh_config() {
    local backup_file="/etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)"
    if cp /etc/ssh/sshd_config "$backup_file"; then
        log_info "SSH配置文件已备份到: $backup_file"
        echo "$backup_file"
    else
        log_error "SSH配置文件备份失败"
        exit 1
    fi
}

# 配置SSH安全设置
configure_ssh_security() {
    local sshd_config="/etc/ssh/sshd_config"
    
    log_info "配置SSH安全设置..."
    
    # 创建临时配置文件
    local temp_config=$(mktemp)
    
    # 读取原配置并修改
    while IFS= read -r line; do
        case "$line" in
            "#PasswordAuthentication"*|"PasswordAuthentication"*)
                echo "# $line - Modified by script $(date +%Y%m%d)" >> "$temp_config"
                echo "PasswordAuthentication no" >> "$temp_config"
                ;;
            "#PubkeyAuthentication"*|"PubkeyAuthentication"*)
                echo "# $line - Modified by script $(date +%Y%m%d)" >> "$temp_config"
                echo "PubkeyAuthentication yes" >> "$temp_config"
                ;;
            "#PermitEmptyPasswords"*|"PermitEmptyPasswords"*)
                echo "# $line - Modified by script $(date +%Y%m%d)" >> "$temp_config"
                echo "PermitEmptyPasswords no" >> "$temp_config"
                ;;
            "#PermitRootLogin"*|"PermitRootLogin"*)
                echo "# $line - Modified by script $(date +%Y%m%d)" >> "$temp_config"
                echo "PermitRootLogin without-password" >> "$temp_config"
                ;;
            "#ChallengeResponseAuthentication"*|"ChallengeResponseAuthentication"*)
                echo "# $line - Modified by script $(date +%Y%m%d)" >> "$temp_config"
                echo "ChallengeResponseAuthentication no" >> "$temp_config"
                ;;
            "#UsePAM"*|"UsePAM"*)
                echo "# $line - Modified by script $(date +%Y%m%d)" >> "$temp_config"
                echo "UsePAM no" >> "$temp_config"
                ;;
            *)
                echo "$line" >> "$temp_config"
                ;;
        esac
    done < "$sshd_config"
    
    # 添加缺失的配置
    grep -q "AuthorizedKeysFile" "$temp_config" || echo "AuthorizedKeysFile .ssh/authorized_keys" >> "$temp_config"
    grep -q "Protocol" "$temp_config" || echo "Protocol 2" >> "$temp_config"

    # 替换原配置文件
    mv "$temp_config" "$sshd_config"
    chmod 600 "$sshd_config"
    
    log_info "SSH安全配置已完成"
}

# 检查SSH配置语法
check_ssh_syntax() {
    if sshd -t > /dev/null 2>&1; then
        log_info "SSH配置语法检查通过"
    else
        log_error "SSH配置语法错误，请检查配置"
        exit 1
    fi
}

# 应用SSH配置
apply_ssh_config() {
    log_info "应用SSH配置..."
    
    check_ssh_syntax
    
    if systemctl reload sshd; then
        log_info "SSH服务重新加载成功"
    else
        log_warn "SSH服务重新加载失败，尝试重启..."
        systemctl restart sshd
    fi
    
    # 验证服务状态
    if systemctl is-active sshd > /dev/null; then
        log_info "SSH服务运行正常"
    else
        log_error "SSH服务异常"
        exit 1
    fi
}

# 显示配置摘要
show_summary() {
    local backup_file="$1"
    
    log_info "=== 系统配置完成 ==="
    echo ""
    echo "📋 配置摘要："
    echo "✅ Hostname: $(hostname)"
    echo "✅ SSH密码认证: 已禁用"
    echo "✅ SSH密钥认证: 已启用"
    echo "✅ Root密码登录: 已禁用"
    echo "✅ 用户密钥: 已配置"
    echo ""
    echo "🔧 连接信息："
    echo "   主机名: $(hostname)"
    echo "   IP地址: $(hostname -I | awk '{print $1}')"
    echo "   用户名: $(logname 2>/dev/null || echo "${SUDO_USER:-$USER}")"
    echo ""
    echo "💾 备份文件: $backup_file"
    echo ""
    log_warn "⚠️  重要提醒："
    echo "   1. 当前SSH连接将继续使用密码认证"
    echo "   2. 新连接必须使用密钥认证"
    echo "   3. 请确保密钥文件安全备份"
    echo ""
    echo "🔄 回滚命令："
    echo "   sudo cp $backup_file /etc/ssh/sshd_config"
    echo "   sudo systemctl restart sshd"
}

# 主函数
main() {
    echo "=== 命令行参数系统配置脚本 ==="
    echo ""
    
    # 解析参数
    parse_arguments "$@"
    
    # 验证参数
    validate_arguments
    
    # 显示预览
    show_preview
    
    # 确认执行
    read -p "是否继续配置？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "操作已取消"
        exit 0
    fi
    
    # 检查权限
    check_root
    
    # 执行配置步骤
    local backup_file=$(backup_ssh_config)
    set_hostname
    setup_ssh_keys
    configure_ssh_security
    apply_ssh_config
    show_summary "$backup_file"
}

# 如果直接执行脚本，调用主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -eq 0 ]]; then
        show_usage
        exit 1
    fi
    main "$@"
fi
