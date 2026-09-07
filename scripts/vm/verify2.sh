#!/bin/bash
# POC-4 / POC-5(近似) 验证（虚拟机执行）
echo "=== POC-4a: 流式中断（2秒后断连）==="
cat > /tmp/req2.json <<'JSON'
{"model":"cmaas-deepseek-v4-flash-0731","messages":[{"role":"user","content":"Count from 1 to 100, one per line"}],"max_tokens":512,"stream":true}
JSON
curl -sS -N -m 2 http://localhost:18080/v1/chat/completions -H 'Content-Type: application/json' --data-binary @/tmp/req2.json | head -c 300
echo
echo "=== POC-4b: 断连后 3 秒 Adapter 仍健康 ==="
sleep 3
curl -sS http://localhost:18080/v1/models
echo
echo "=== POC-5 近似: docker restart 恢复 ==="
docker restart deploy-confidential-adapter-1
sleep 6
docker ps --filter name=deploy-confidential-adapter-1 --format 'STATUS: {{.Status}}'
curl -sS http://localhost:18080/v1/models
echo
echo "=== POC-5 补充: 重启后正常推理 ==="
curl -sS http://localhost:18080/v1/chat/completions -H 'Content-Type: application/json' --data-binary @/tmp/req1.json
