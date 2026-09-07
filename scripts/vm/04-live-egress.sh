#!/bin/bash
# live 请求期间采样容器出站连接，确定运行时实际 egress 目标
set -u
CONTAINER=deploy-confidential-adapter-1
MODEL=cmaas-deepseek-v4-flash-0731
OUT=/tmp/ss-sample.txt

rm -f "$OUT"

echo "=== 发起长流式请求（后台）==="
curl -sS -N --max-time 40 "http://127.0.0.1:18080/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"请从 1 开始连续输出整数到 1500，每行一个不要停。\"}],\"max_tokens\":8192,\"stream\":true}" \
  > /tmp/live-stream.out 2>&1 &
CURL_PID=$!

# 采样 8 次，每次间隔 0.7s
for i in $(seq 1 8); do
  sleep 0.7
  echo "--- sample $i ---" >> "$OUT"
  docker exec "$CONTAINER" ss -tnp 2>/dev/null | grep -vE 'State|LISTEN' >> "$OUT" 2>&1
done

# 等待 curl 结束
wait "$CURL_PID" 2>/dev/null
echo "curl 退出码: $?"

echo "=== 采样到的非本地 TCP 连接（去重对端 IP:port）==="
grep -E 'ESTAB|SYN-SENT' "$OUT" | awk '{print $4}' | grep -vE '127.0.0.1|::1' | sort -u

echo "=== 全部采样原始内容 ==="
cat "$OUT"

echo "=== 反查对端 IP ==="
for ip in $(grep -E 'ESTAB|SYN-SENT' "$OUT" | awk '{print $4}' | sed 's/:[0-9]*$//' | grep -vE '127.0.0.1|::1|^\*' | sort -u); do
  echo "--- $ip ---"
  docker exec "$CONTAINER" sh -c "getent hosts $ip 2>/dev/null || echo '(无 PTR)'"
done

echo "=== 流结果判定 ==="
grep -q '\[DONE\]' /tmp/live-stream.out && echo "流正常收尾 [DONE]" || echo "流未收尾"
wc -c < /tmp/live-stream.out
