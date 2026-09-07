#!/bin/bash
# 阶段 4.7.2 运行时依赖冻结：从报告/材质 + 实时连接观测 SDK 出站目标
set -u
VOLUME=deploy_cmaas-reports
IMAGE=confidential-adapter:0.1.0-poc
RD=/var/lib/cmaas/reports

echo "=== 1. 报告 JSONL 首条记录（脱敏后字段结构）==="
docker run --rm --entrypoint sh -v "$VOLUME:$RD" "$IMAGE" -c "head -n1 $RD/reports-*.jsonl" 2>&1

echo ""
echo "=== 2. attestation-materials 清单 ==="
docker run --rm --entrypoint sh -v "$VOLUME:$RD" "$IMAGE" -c "ls -la $RD/attestation-materials/ && find $RD/attestation-materials -type f" 2>&1

echo ""
echo "=== 3. 报告+材质中的主机名/URL 线索 ==="
docker run --rm --entrypoint sh -v "$VOLUME:$RD" "$IMAGE" -c "grep -rEoh 'https?://[a-zA-Z0-9._-]+' $RD 2>/dev/null | sort -u" 2>&1

echo ""
echo "=== 4. 容器当前已建立 TCP 连接（对端 IP:端口）==="
docker exec deploy-confidential-adapter-1 ss -tnp 2>&1 | grep -E 'ESTAB|SYN-SENT' | head -n 30

echo ""
echo "=== 5. 解析 CMAAS endpoint 与已知依赖域名 ==="
for h in ws-la2jmsuqq2d1zfv2.cn-beijing.maas.aliyuncs.com rekor.sigstore.dev; do
  echo "--- $h ---"
  docker exec deploy-confidential-adapter-1 sh -c "getent hosts $h 2>/dev/null || nslookup $h 2>&1 | tail -n5"
done
