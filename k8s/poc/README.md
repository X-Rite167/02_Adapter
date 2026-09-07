# POC 集群部署指引（在有 Docker + kubectl 的机器上执行）

## 0. 前置

- Docker 可达构建机网络：`codeload.github.com`、`goproxy.cn`（2026-09-03 实测本机可达）。
- kubectl 可访问目标集群，namespace `litellm` 已存在。
- `.env` 中的 `<WORKSPACE_ID>` 与 `DASHSCOPE_API_KEY`。

## 1. 构建镜像

```bash
docker build -t <IMAGE_REGISTRY>/confidential-adapter:0.1.0-poc .
docker push <IMAGE_REGISTRY>/confidential-adapter:0.1.0-poc
```

## 2. 替换占位符后部署

1. `k8s/poc/deployment.yaml`：替换 `<IMAGE_REGISTRY>` 与 `<WORKSPACE_ID>`。
2. `k8s/poc/secret.yaml`：替换 `DASHSCOPE_API_KEY`（从 `.env` 复制）。

```bash
kubectl apply -f k8s/poc/secret.yaml
kubectl apply -f k8s/poc/service.yaml
kubectl apply -f k8s/poc/deployment.yaml
kubectl -n litellm rollout status deploy/confidential-adapter
kubectl -n litellm get pods -l app=confidential-adapter
```

## 3. 集群内连通验证（POC-3 基础项）

```bash
# 从 LiteLLM Pod 内验证（预期 200 与模型列表）
kubectl -n litellm exec -it deploy/<litellm-deploy> -- curl -sS http://confidential-adapter.litellm.svc.cluster.local:8080/v1/models
```

## 4. 后续 POC-3/4/5

- POC-3：NetworkPolicy 最小化验证 → `scripts/poc/02-cluster-network-check.ps1`（在有 kubectl 的机器执行）。
- POC-4：取消传播/零重试 → 按 `docs/poc-test-cases.md` 执行。
- POC-5：滚动更新与长 SSE → 按 `docs/poc-test-cases.md` 执行。

## 5. 验证完成后的 LiteLLM 端到端调用

```bash
curl -sS http://<litellm-service>:4000/v1/chat/completions \
  -H "Authorization: Bearer <litellm-key>" \
  -H "Content-Type: application/json" \
  -d '{"model":"deepseek-v4-confidential","messages":[{"role":"user","content":"只返回 CONFIDENTIAL_OK"}],"max_tokens":16,"stream":false}'
```
