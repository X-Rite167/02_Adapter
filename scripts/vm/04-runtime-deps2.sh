#!/bin/bash
# 深挖 attestation material JSON 中的 collateral/URL 线索
set -u
VOLUME=deploy_cmaas-reports
IMAGE=confidential-adapter:0.1.0-poc
RD=/var/lib/cmaas/reports

echo "=== 1. 材质 JSON 顶层字段 ==="
docker run --rm --entrypoint sh -v "$VOLUME:$RD" "$IMAGE" -c "head -c 2000 $RD/attestation-materials/*.json | head -c 2000" 2>&1

echo ""
echo "=== 2. 材质中的全部 URL/host（含引号内）==="
docker run --rm --entrypoint sh -v "$VOLUME:$RD" "$IMAGE" -c "grep -rhoE 'https?://[^\"\\ ]+' $RD/attestation-materials/ 2>/dev/null | sort -u" 2>&1

echo ""
echo "=== 3. 材质中的域名关键字（pccs/pck/tdx/intel/cert/quote）==="
docker run --rm --entrypoint sh -v "$VOLUME:$RD" "$IMAGE" -c "grep -rhoiE '[a-z0-9.-]+\.(intel\.com|aliyuncs\.com|aliyun\.com|sigstore\.dev|googleapis\.com|com|cn|dev|io)' $RD/attestation-materials/ 2>/dev/null | sort -u | head -n 50" 2>&1

echo ""
echo "=== 4. 首次请求时的容器日志（attestation/verify 网络线索）==="
docker logs deploy-confidential-adapter-1 2>&1 | grep -iE 'attest|verify|pccs|collateral|rekor|tlog|fetch|http|dial' | head -n 30
