#!/bin/bash
# 每月流量重置脚本

# 清除iptables规则
iptables -D OUTPUT -o eth0 -j TRAFFIC_CTRL 2>/dev/null
iptables -F TRAFFIC_CTRL 2>/dev/null
iptables -X TRAFFIC_CTRL 2>/dev/null

# 删除状态文件
rm -f /var/lock/traffic_ctrl.lock

# 重置vnstat计数器
vnstat --delete --force -i eth0
vnstat -u -i eth0

# 保存防火墙配置
netfilter-persistent save