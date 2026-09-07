#!/bin/bash
# 阶段 4 Docker 实测：环境检查
echo '---docker ps---'
docker ps --format '{{.Names}}|{{.Status}}|{{.Ports}}'
echo '---tools---'
for t in curl jq dig nslookup tcpdump ss; do
  if which "$t" >/dev/null 2>&1; then echo "$t: ok"; else echo "$t: MISSING"; fi
done
echo '---compose---'
docker compose version 2>&1 | head -n1
echo '---adapter logs tail---'
docker logs --tail 5 deploy-confidential-adapter-1 2>&1
