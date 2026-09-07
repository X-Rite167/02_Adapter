#!/bin/bash
# Adapter 端到端验证脚本（在虚拟机执行）
echo "=== 非流式 ==="
cat > /tmp/req1.json <<'JSON'
{"model":"cmaas-deepseek-v4-flash-0731","messages":[{"role":"user","content":"Reply CONFIDENTIAL_OK only"}],"max_tokens":16}
JSON
curl -sS http://localhost:18080/v1/chat/completions -H 'Content-Type: application/json' --data-binary @/tmp/req1.json
echo
echo "=== 流式(尾部700字节) ==="
cat > /tmp/req2.json <<'JSON'
{"model":"cmaas-deepseek-v4-flash-0731","messages":[{"role":"user","content":"Reply CONFIDENTIAL_OK only"}],"max_tokens":16,"stream":true}
JSON
curl -sS -N http://localhost:18080/v1/chat/completions -H 'Content-Type: application/json' --data-binary @/tmp/req2.json | tail -c 700
echo
echo "=== 未知模型拒绝行为 ==="
cat > /tmp/req3.json <<'JSON'
{"model":"not-in-whitelist","messages":[{"role":"user","content":"x"}]}
JSON
curl -sS -w "\nHTTP_STATUS:%{http_code}\n" http://localhost:18080/v1/chat/completions -H 'Content-Type: application/json' --data-binary @/tmp/req3.json
