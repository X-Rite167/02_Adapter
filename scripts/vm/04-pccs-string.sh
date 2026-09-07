#!/bin/bash
# 从 cmaas-audit 二进制扫描内置 PCCS/DCAP/trustedservices URL
set -u
IMAGE=confidential-adapter:0.1.0-poc

echo "=== 扫描 cmaas-audit 二进制中的 URL/host 线索 ==="
docker run --rm --entrypoint sh "$IMAGE" -c "strings /usr/local/bin/cmaas-audit 2>/dev/null | grep -iE 'https?://|trustedservices|pccs|dcap|sgx|tdx|intel|aliyun|rekor|sigstore' | sort -u | head -n 60" 2>&1

echo ""
echo "=== 扫描 openai-proxy 二进制同样线索 ==="
docker run --rm --entrypoint sh "$IMAGE" -c "strings /usr/local/bin/openai-proxy 2>/dev/null | grep -iE 'https?://|trustedservices|pccs|dcap|sgx|tdx|intel|aliyun|rekor|sigstore' | sort -u | head -n 60" 2>&1
