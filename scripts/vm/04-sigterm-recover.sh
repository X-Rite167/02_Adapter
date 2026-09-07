#!/bin/bash
# SIGTERM 退出码确认 + 恢复容器 + 恢复后连通验证
set -u
CONTAINER=deploy-confidential-adapter-1

echo "=== 1. 退出码与重启策略 ==="
docker inspect -f 'ExitCode={{.State.ExitCode}} OOMKilled={{.State.OOMKilled}} Error={{.State.Error}}' "$CONTAINER"
docker inspect -f 'RestartPolicy={{.HostConfig.RestartPolicy.Name}}' "$CONTAINER"

echo "=== 2. 重启容器 ==="
docker start "$CONTAINER"
echo "docker start 退出码: $?"

echo "=== 3. 等待就绪（最多 20s）==="
for i in $(seq 1 20); do
  CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://127.0.0.1:18080/v1/models" 2>/dev/null)
  if [ "$CODE" = "200" ]; then echo "就绪 (${i}s), HTTP $CODE"; break; fi
  sleep 1
done

echo "=== 4. 恢复后非流式请求 ==="
curl -sS --max-time 30 "http://127.0.0.1:18080/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"cmaas-deepseek-v4-flash-0731","messages":[{"role":"user","content":"Reply CONFIDENTIAL_OK only"}],"max_tokens":16,"stream":false}' \
  -w "\nHTTP_STATUS=%{http_code}\n" 2>&1

echo "=== 5. 最终容器状态 ==="
docker inspect -f 'Running={{.State.Running}} RestartCount={{.RestartCount}} Status={{.State.Status}}' "$CONTAINER"
