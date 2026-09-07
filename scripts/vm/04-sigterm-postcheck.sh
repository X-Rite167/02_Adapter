#!/bin/bash
# SIGTERM 后状态确认：进程是否存活、端口是否仍监听、是否还能服务新请求
set -u
CONTAINER=deploy-confidential-adapter-1

echo "=== 1. 容器内进程（openai-proxy 是否存活）==="
docker exec "$CONTAINER" ps -ef 2>&1 | grep -v grep | head -n 20

echo "=== 2. 端口监听状态 ==="
docker exec "$CONTAINER" ss -tlnp 2>&1 | head -n 20

echo "=== 3. 发一个新请求（非流式）==="
curl -sS --max-time 30 "http://127.0.0.1:18080/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"cmaas-deepseek-v4-flash-0731","messages":[{"role":"user","content":"Reply CONFIDENTIAL_OK only"}],"max_tokens":16,"stream":false}' \
  -w "\nHTTP_STATUS=%{http_code}\n" 2>&1

echo "=== 4. 容器运行时长与重启次数 ==="
docker inspect -f 'StartedAt={{.State.StartedAt}} RestartCount={{.RestartCount}} Running={{.State.Running}} Status={{.State.Status}}' "$CONTAINER"
