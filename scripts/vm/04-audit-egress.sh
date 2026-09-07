#!/bin/bash
# 审计路径 egress 采样：attestation verify + transparency-log list 期间连接
set -u
VOLUME=deploy_cmaas-reports
IMAGE=confidential-adapter:0.1.0-poc
RD=/var/lib/cmaas/reports
REPORT=$(ls /dev/null >/dev/null 2>&1; docker run --rm --entrypoint sh -v "$VOLUME:$RD" "$IMAGE" -c "ls $RD/reports-*.jsonl | head -n1")
ID=$(docker run --rm --entrypoint sh -v "$VOLUME:$RD" "$IMAGE" -c "sed -n 's/.*request_id.:.\([a-f0-9-]*\).*/\1/p' $REPORT" | head -n1)
echo "REPORT=$REPORT"
echo "REQ_ID=$ID"

# 后台跑一个临时容器执行 verify + list，同时采样宿主机对该容器的 netstat
docker run --rm --name audit-egress-test --entrypoint cmaas-audit -v "$VOLUME:$RD" "$IMAGE" \
  attestation verify --report "$REPORT" --request-id "$ID" >/tmp/audit-verify.out 2>&1 &
AUDIT_PID=$!

OUT=/tmp/audit-nstat.txt
rm -f "$OUT"
for i in $(seq 1 6); do
  sleep 1
  echo "--- s$i ---" >> "$OUT"
  docker exec audit-egress-test netstat -tn 2>/dev/null | grep -vE '^Active|^Proto' >> "$OUT" 2>&1 || true
done

wait "$AUDIT_PID" 2>/dev/null
echo "=== attestation verify 输出 ==="
cat /tmp/audit-verify.out

echo "=== verify 期间采样 ==="
cat "$OUT"
echo "=== 对端 IP 去重 ==="
grep -E 'ESTABLISHED|SYN_SENT' "$OUT" | awk '{print $5}' | sed 's/:[0-9]*$//' | grep -vE '127.0.0.1|::1|^\*' | sort -u

echo ""
echo "=== transparency-log list 采样 ==="
docker run --rm --name audit-tlog-test --entrypoint cmaas-audit -v "$VOLUME:$RD" "$IMAGE" \
  transparency-log list --report "$REPORT" --request-id "$ID" >/tmp/audit-tlog.out 2>&1 &
TL_PID=$!
OUT2=/tmp/tlog-nstat.txt
rm -f "$OUT2"
for i in $(seq 1 6); do
  sleep 1
  echo "--- s$i ---" >> "$OUT2"
  docker exec audit-tlog-test netstat -tn 2>/dev/null | grep -vE '^Active|^Proto' >> "$OUT2" 2>&1 || true
done
wait "$TL_PID" 2>/dev/null
cat /tmp/audit-tlog.out
echo "=== tlog 采样 ==="
cat "$OUT2"
echo "=== 对端 IP 去重 ==="
grep -E 'ESTABLISHED|SYN_SENT' "$OUT2" | awk '{print $5}' | sed 's/:[0-9]*$//' | grep -vE '127.0.0.1|::1|^\*' | sort -u

# 反查所有对端 IP
echo "=== 反查对端 IP ==="
for ip in $(cat "$OUT" "$OUT2" | grep -E 'ESTABLISHED|SYN_SENT' | awk '{print $5}' | sed 's/:[0-9]*$//' | grep -vE '127.0.0.1|::1|^\*' | sort -u); do
  echo "--- $ip ---"
  docker run --rm --entrypoint sh "$IMAGE" -c "getent hosts $ip 2>/dev/null || echo '(无 PTR)'"
done
