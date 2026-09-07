#!/bin/bash
# 精确提取 PCCS/DCAP 默认 base URL 与所有 FQDN
set -u
IMAGE=confidential-adapter:0.1.0-poc
echo "=== 含 .aliyuncs.com / aliyun / intel / sigstore / trustedservices 的完整字符串 ==="
docker run --rm --entrypoint sh "$IMAGE" -c "strings /usr/local/bin/cmaas-audit 2>/dev/null | grep -oE '[a-zA-Z0-9._-]+\.(aliyuncs\.com|aliyun\.com|intel\.com|sigstore\.dev|trustedservices\.intel\.com|azure-api\.net)' | sort -u" 2>&1

echo ""
echo "=== 含 https:// 的字符串片段 ==="
docker run --rm --entrypoint sh "$IMAGE" -c "strings /usr/local/bin/cmaas-audit 2>/dev/null | grep -oE 'https://[^ ]*' | sort -u | head -n 40" 2>&1

echo ""
echo "=== 默认 PCCS 配置常量（含 default 附近）==="
docker run --rm --entrypoint sh "$IMAGE" -c "strings /usr/local/bin/cmaas-audit 2>/dev/null | grep -iE 'pccs|api/sgx|api/tdx|qe/identity|qe/certification|pck|certification\.v[0-9]|sgx/certification|tdx/certification|attestation' | sort -u | head -n 40" 2>&1
