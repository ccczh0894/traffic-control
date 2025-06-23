#!/bin/bash
# 出站流量控制脚本 v2.1

# ----------------------------
# 配置区（按需修改）
# ----------------------------
LOG_FILE="/var/log/traffic_ctrl.log"  # 日志文件路径
THRESHOLD_GB=1000                     # 流量阈值(GB)
LOCK_FILE="/var/lock/traffic_ctrl.lock" # 状态锁文件
INTERFACE="eth0"                      # 外网接口，根据实际更改
SSH_PORT=22                           # SSH端口，根据实际更改
VNSTAT_IF="$INTERFACE"                # vnstat监控接口

# ----------------------------
# 函数：写日志
# ----------------------------
log() {
    echo "$(date "+%Y-%m-%d %H:%M:%S") - $1" >> "$LOG_FILE"
}

# ----------------------------
# 主逻辑
# ----------------------------
{
    # 获取当月流量数据
    json_data=$(vnstat --json m 2>/dev/null)
    if [ $? -ne 0 ]; then
        log "错误：vnstat数据获取失败！"
        exit 1
    fi

    # 提取当前月份流量
    current_month=$(date +%Y-%m)
    traffic_data=$(jq -r ".interfaces[] | select(.name==\"$VNSTAT_IF\").traffic.month[] | select(.date.year==$(date +%Y) and .date.month==$(date +%m))" <<< "$json_data")

    rx=$(jq -r '.rx' <<< "$traffic_data")      # 获取入站流量
    tx=$(jq -r '.tx' <<< "$traffic_data")      # 获取出站流量
	total_bytes=$tx                            # 统计出站流量
	# total_bytes=$((rx + tx))                 # 总流量 = 入站 + 出站
	total_gb=$(echo "scale=2; $total_bytes/(1024^3)" | bc)

    log "本月出站流量：${total_gb}GB / 阈值：${THRESHOLD_GB}GB"

    # 流量判断
    if (( $(echo "$total_gb >= $THRESHOLD_GB" | bc -l) )); then
        if [ ! -f "$LOCK_FILE" ]; then
            log "流量超限，启用限制规则..."

            # 创建专用链
            iptables -N TRAFFIC_CTRL 2>/dev/null
            iptables -F TRAFFIC_CTRL

            # 放行规则
            iptables -A TRAFFIC_CTRL -p tcp --dport $SSH_PORT -j ACCEPT
            iptables -A TRAFFIC_CTRL -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
            iptables -A TRAFFIC_CTRL -j DROP

            # 挂载到OUTPUT链
            iptables -I OUTPUT -o $INTERFACE -j TRAFFIC_CTRL

            # 持久化规则
            netfilter-persistent save

            # 创建锁文件
            touch "$LOCK_FILE"
        fi
    else
        if [ -f "$LOCK_FILE" ]; then
            log "流量未超限，解除限制..."
            
            # 清除规则
            iptables -D OUTPUT -o $INTERFACE -j TRAFFIC_CTRL 2>/dev/null
            iptables -F TRAFFIC_CTRL 2>/dev/null
            iptables -X TRAFFIC_CTRL 2>/dev/null
            
            # 删除锁文件
            rm -f "$LOCK_FILE"
        fi
    fi
} >> "$LOG_FILE" 2>&1