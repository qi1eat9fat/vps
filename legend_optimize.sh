#!/bin/bash

# 定义颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== 开始针对 512MB 内存/2GB 硬盘 VPS 进行优化 ===${NC}"

# 1. 检查是否为 Root
if [ "$EUID" -ne 0 ]; then 
  echo "请使用 root 权限运行此脚本"
  exit
fi

# 2. 更新源并安装必要工具 (ZRAM)
echo -e "${YELLOW}>> [1/5] 安装 ZRAM 及必要组件...${NC}"
apt update -y
apt install zram-tools curl wget -y

# 3. 配置 ZRAM (内存压缩)
# 设置 60% 内存作为 ZRAM，使用 lz4 算法 (CPU占用低)
echo -e "${YELLOW}>> [2/5] 配置 ZRAM 策略...${NC}"
cat > /etc/default/zramswap <<EOF
ALGO=lz4
PERCENT=60
EOF
# 重启 ZRAM 服务
service zramswap reload || systemctl restart zramswap

# 4. 系统内核参数调优 (BBR + 内存策略)
echo -e "${YELLOW}>> [3/5] 开启 BBR 并优化内核参数...${NC}"

# 备份原始配置
cp /etc/sysctl.conf /etc/sysctl.conf.bak

# 写入新配置
cat >> /etc/sysctl.conf <<EOF

# --- 优化脚本添加 ---
# 开启 BBR
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# 内存使用策略
# swappiness=10: 尽量不使用硬盘 Swap，优先用 ZRAM
vm.swappiness=10
# vfs_cache_pressure=50: 稍微保留一些文件索引缓存，避免频繁读盘
vm.vfs_cache_pressure=50

# 增加系统最大文件打开数 (代理服务需要)
fs.file-max = 65535
EOF

# 应用参数
sysctl -p

# 5. 限制日志大小 (防爆盘)
echo -e "${YELLOW}>> [4/5] 限制系统日志大小 (Max 50MB)...${NC}"
# 修改 journald 配置
sed -i 's/#SystemMaxUse=/SystemMaxUse=50M/g' /etc/systemd/journald.conf
# 如果上面没替换成功（因为有的版本默认没有该行），追加一行
grep -q "SystemMaxUse=50M" /etc/systemd/journald.conf || echo "SystemMaxUse=50M" >> /etc/systemd/journald.conf
# 立即清理旧日志
journalctl --vacuum-size=50M

# 6. 清理垃圾与收尾
echo -e "${YELLOW}>> [5/5] 清理软件包缓存...${NC}"
apt autoremove -y
apt clean

echo -e "${GREEN}=== 优化完成！ ===${NC}"
echo -e "当前状态检查："
echo -e "1. BBR 状态 (应显示 bbr): $(sysctl -n net.ipv4.tcp_congestion_control)"
echo -e "2. ZRAM 状态:"
zramctl
echo -e "---------------------------------"
echo -e "建议立即重启服务器以确保所有设置生效: reboot"
