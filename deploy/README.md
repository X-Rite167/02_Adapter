# 虚拟机 Docker 链路验证指引

## 1. 拷贝到虚拟机

把整个 `02_Adapter` 目录（或至少 `.env`、`Dockerfile`、`deploy/`）拷贝到装有 Docker 的 Linux 虚拟机。

## 2. 启动

```bash
cd 02_Adapter/deploy
docker compose --env-file ../.env up --build -d
docker compose ps
```

> Adapter 镜像构建在虚拟机上执行，同样需要 `codeload.github.com` / `goproxy.cn` 可达；`golang:1.24.3` 与 `alpine:3.20` 基础镜像拉取走虚拟机的镜像加速配置。
> `litellm` 镜像 `ghcr.io/berriai/litellm:main-stable` 如拉取失败，请告知我换可用的镜像源/tag。

## 3. 验证清单（对应 docs/poc-test-cases.md）

> 虚拟机仅部署 Adapter（LiteLLM 已在 K8s 构建好）。

### 3.1 Adapter 直连（宿主机或内网任意主机）

```bash
curl -sS http://<虚拟机IP>:18080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"cmaas-deepseek-v4-flash-0731","messages":[{"role":"user","content":"Reply CONFIDENTIAL_OK only"}],"max_tokens":16}'
```

预期：200 + `"content":"CONFIDENTIAL_OK"`。

### 3.2 流式（验证 SSE 与 usage chunk）

```bash
curl -sS -N http://<虚拟机IP>:18080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"cmaas-deepseek-v4-flash-0731","messages":[{"role":"user","content":"Reply CONFIDENTIAL_OK only"}],"max_tokens":16,"stream":true}'
```

预期：多个 `chat.completion.chunk` + `[DONE]`。

### 3.3 K8s LiteLLM 接入本 Adapter（可选，需集群到虚拟机网络可达）

把 LiteLLM 的 `api_base` 改为 `http://<虚拟机IP>:18080/v1`，业务侧即可通过 `deepseek-v4-confidential` 走本 Adapter。若集群网络不通，等 Adapter 部署进 kite 平台后再切换（api_base 用 ClusterIP 域名）。

## 4. Docker 环境可覆盖的 POC 与 K8s 专属项

| POC | Docker 环境 | K8s 环境 |
|---|---|---|
| POC-1 协议兼容 | ✅ 全部可测 | — |
| POC-2 拒绝行为 | ✅ 大部分可测 | 未知 endpoint 补充 |
| POC-3 调用方限制 | ❌ 无 NetworkPolicy | ✅ 唯一环境 |
| POC-4 取消/零重试 | ✅ `docker restart` 模拟 + 断连测试 | 补充 |
| POC-5 滚动排空 | ⚠️ `docker stop`/restart 近似测进程级行为 | ✅ 真实滚动更新 |

POC-4 用例（在虚拟机执行）：
```bash
# 流式中途 Ctrl+C 断连，然后看 Adapter 日志确认上游及时关闭、无重试
docker logs -f 02_Adapter-confidential-adapter-1
```

POC-5 近似用例：
```bash
# 长流进行中重启 Adapter，观察 LiteLLM 侧报错与流中断行为
docker restart 02_Adapter-confidential-adapter-1
```

## 5. 清理

```bash
docker compose down
docker volume rm deploy_cmaas-reports   # 如需保留透明度报告则不要删
```
