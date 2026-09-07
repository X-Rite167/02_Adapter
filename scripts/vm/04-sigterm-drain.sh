#!/bin/bash
# 阶段 4.7.3 SIGTERM 排空实测（POC-5.1 近似，Docker 环境）
# 目标：只记录事实——长 SSE 流进行中发送 SIGTERM，观察流是否收尾、容器是否退出/重启
set -u
HOST=127.0.0.1:18080
OUT=/tmp/sigterm-stream.out
CONTAINER=deploy-confidential-adapter-1
MODEL=cmaas-deepseek-v4-flash-0731

rm -f "$OUT"

echo "=== 1. 启动长流式请求（后台）==="
curl -sS -N --max-time 90 "http://$HOST/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"请从 1 开始连续输出整数，每行一个，一直输出到 2000，中间不要停。\"}],\"max_tokens\":8192,\"stream\":true}" \
  > "$OUT" 2>&1 &
CURL_PID=$!

# 等流式开始
sleep 2
if ! kill -0 "$CURL_PID" 2>/dev/null; then
  echo "WARN: curl 已在 SIGTERM 前结束（流太短），结果如下"
  cat "$OUT"
  exit 0
fi

echo "=== 2. 流进行中发送 SIGTERM 到容器 ==="
T0=$(date +%s)
docker kill --signal=TERM "$CONTAINER"
echo "docker kill SIGTERM 退出码: $?"

echo "=== 3. 等待 curl 结束（最长 30s）==="
wait "$CURL_PID" 2>/dev/null
CURL_RC=$?
T1=$(date +%s)
echo "curl 退出码: $CURL_RC"
echo "SIGTERM 后到流结束耗时(秒): $((T1-T0))"

echo "=== 4. 流内容判定 ==="
echo "输出字节数: $(wc -c < "$OUT")"
echo "chunk 数量: $(grep -c '^data:' "$OUT")"
if grep -q '\[DONE\]' "$OUT"; then echo "RESULT: 流正常收尾 [DONE]"; else echo "RESULT: 流被中断，无 [DONE]"; fi
echo "--- 末 3 行 ---"
tail -n3 "$OUT"

echo "=== 5. 容器状态（是否退出/重启）==="
docker ps -a --filter "name=$CONTAINER" --format '{{.Status}}'

echo "=== 6. 容器日志（信号处理线索）==="
docker logs --tail 15 "$CONTAINER" 2>&1
