#!/bin/bash
# 确认容器内可用网络观测工具
set -u
CONTAINER=deploy-confidential-adapter-1
echo "=== busybox/netstat/ss 是否可用 ==="
docker exec "$CONTAINER" sh -c "which netstat ss cat awk 2>&1"
echo "=== 用 busybox netstat 试看连接 ==="
docker exec "$CONTAINER" sh -c "netstat -tn 2>&1 | head -n 30"
echo "=== /proc/net/tcp 读取测试（需 root）==="
docker exec --user root "$CONTAINER" sh -c "head -n 5 /proc/net/tcp 2>&1"
