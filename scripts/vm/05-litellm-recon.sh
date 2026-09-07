#!/bin/bash
# 阶段 5 前置：摸清 VM 上 litellm 容器现状
set -u
echo "=== litellm 容器详情 ==="
docker inspect litellm --format 'Image={{.Config.Image}} Cmd={{.Config.Cmd}} Entrypoint={{.Config.Entrypoint}}' 2>&1
echo ""
echo "=== litellm 环境变量（脱敏：仅看关键项）==="
docker exec litellm env 2>/dev/null | grep -iE 'LITELLM|CONFIG|MASTER_KEY|SALT|STORE|DATABASE|API_BASE|CMAAS' | sed 's/=.*KEY.*/=***/' 2>&1
echo ""
echo "=== litellm 挂载的配置 ==="
docker inspect litellm --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}' 2>&1
echo ""
echo "=== litellm 健康状态 ==="
docker ps --filter name=litellm --format '{{.Names}}|{{.Status}}'
echo ""
echo "=== 从 litellm 容器内访问 Adapter（预期 200 模型列表）==="
docker exec litellm sh -c "curl -sS --max-time 5 http://192.168.200.128:18080/v1/models 2>&1 | head -c 500" 2>&1
echo ""
echo "=== litellm /v1/models（看它当前暴露的模型）==="
curl -sS --max-time 5 http://127.0.0.1:4000/v1/models 2>&1 | head -c 1000
