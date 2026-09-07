#!/bin/bash
# live 请求期间用 busybox netstat 采样容器出站连接
set -u
CONTAINER=deploy-confidential-adapter-1
MODEL=cmaas-deepseek-v4-flash-0731
OUT=/tmp/nstat-sample.txt

rm -f "$OUT"

echo "=== 发起长流式请求（后台，约 40s）==="
curl -sS -N --max-time 40 "http://127.0.0.1:18080/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"请从 1 开始连续输出整数到 1500，每行一个不要停。\"}],\"max_tokens\":8192,\"stream\":true}" \
  > /tmp/live-stream.out 2>&1 &
CURL_PID=$!

for i in $(seq 1 10); do
  sleep 1
  echo "--- sample $i ---" >> "$OUT"
  docker exec "$CONTAINER" netstat -tn 2>/dev/null | grep -vE '^Active|^Proto' >> "$OUT" 2>&1
done

wait "$CURL_PID" 2>/dev/null
echo "curl 退出码: $?"

for i in $(seq 1 3); do
  sleep 1
  echo "--- post $i ---" >> "$OUT"
  docker exec "$CONTAINER" netstat -tn 2>/dev/null | grep -vE '^Active|^Proto' >> "$OUT" 2>&1
done

echo "=== 全部采样原始内容 ==="
cat "$OUT"

echo "=== 去重对端 IP:port（非本地）==="
grep -E 'ESTABLISHED|SYN_SENT|TIME_WAIT' "$OUT" | awk '{print $5}' | sort -u

echo "=== 反查对端 IP ==="
for ip in $(grep -E 'ESTABLISHED|SYN_SENT|TIME_WAIT' "$OUT" | awk '{print $5}' | sed 's/:[0-9]*$//' | grep -vE '127.0.0.1|::1|^\*' | sort -u); do
  echo "--- $ip ---"
  docker exec "$CONTAINER" sh -c "getent hosts $ip 2>/dev/null || echo '(无 PTR)'"
done

echo "=== 流结果判定 ==="
grep -q '\[DONE\]' /tmp/live-stream.out && echo "流正常收尾 [DONE]" || echo "流未收尾"
echo "输出字节数: $(wc -c < /tmp/live-stream.out)"
