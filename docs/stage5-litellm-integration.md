# 阶段 5：公司 LiteLLM 接入 CMAAS Adapter 指南

> 状态（2026-09-04 验证通过）：对接目标为公司已有 LiteLLM（**v1.95.0**，admin UI 维护，`https://aihub.yiling.cn`）。
> 网络路径：Cloudflare Quick Tunnel 把 VM Adapter `18080` 临时暴露为公网 HTTPS。
> **端到端验证结果**：`/v1/models` 含 `deepseek-v4-confidential` ✅；非流式 `CONFIDENTIAL_OK` ✅；SSE 逐块输出并 `[DONE]` 结束 ✅。
> ⚠️ 隧道是**临时联调手段**（随机 URL、公网暴露计费端点、无鉴权），验证完必须关闭；生产走 K8s ClusterIP + NetworkPolicy。

## 1. 接入目标

```text
业务应用
  -> 公司 LiteLLM（唯一业务模型目录、鉴权、配额、路由）
      -> CMAAS Adapter（openai-proxy，形态 A）
          -> 阿里云 Confidential MaaS Endpoint
```

- LiteLLM 独占逻辑模型名、Provider 选择、业务鉴权。
- Adapter 只暴露一个后端模型，不接受请求体动态切换。
- 业务侧只看到 `deepseek-v4-confidential`，看不到 WorkspaceId、后端 code、Adapter/DashScope key。

## 2. admin UI 填法（LiteLLM 1.95.0，当前维护方式）

维护方式为 admin UI（`STORE_MODEL_IN_DB`），模型 `deepseek-v4-confidential` 已创建，进入 **Models + Endpoints → 点开该模型 → Edit Settings** 修改以下字段：

| admin UI 字段 | 填的值 | 说明 |
|---|---|---|
| Public Model Name（`model_name`） | `deepseek-v4-confidential` | 业务调用名，保持不变 |
| Provider | `Custom OpenAI / OpenAI Compatible`（`custom_llm_provider=custom_openai`） | 走 OpenAI 兼容接口指向官方代理 |
| Litellm Model Name（`litellm_params.model`） | `cmaas-deepseek-v4-flash-0731` | **后端模型 code**（custom_openai 不带 `openai/` 前缀） |
| API Base（`api_base`） | `https://father-starsmerchant-bizarre-upcoming.trycloudflare.com/v1` | **临时隧道**（cloudflared 每次重启会换随机 URL） |
| API Key | 任意非空占位（实测用 `123456789`） | 形态 A 的 openai-proxy 不校验 Authorization，**但 LiteLLM 要求非空** |
| Max Retries | `0` | 硬约束：防重复计费（admin UI 若无此栏，见下方 REST 兜底） |
| Timeout | `300` | 推理耗时长 |
| Cache | 关闭 / `false` | 明文不进缓存 |

> 等价 REST（需 `STORE_MODEL_IN_DB=True` + Master Key）：
> ```bash
> curl -X POST "https://aihub.yiling.cn/model/new" \
>   -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
>   -H "Content-Type: application/json" \
>   -d '{"model_name":"deepseek-v4-confidential","litellm_params":{"model":"cmaas-deepseek-v4-flash-0731","api_base":"https://father-starsmerchant-bizarre-upcoming.trycloudflare.com/v1","api_key":"cmaas-placeholder","max_retries":0,"timeout":300,"cache":false}}'
> ```

> **⚠️ 必查：你当前 Raw JSON 缺少 `max_retries` / `timeout` / `cache` 字段**（只有 `custom_llm_provider` 等）。
> admin UI 的 Add/Edit 表单若没有这三栏，需用 `POST /model/update`（`litellm_params` 带 `max_retries:0`、`timeout:300`、`cache:false`）补设，或用 `litellm_settings.num_retries: 0` 全局兜底。这是**防重复计费 + 明文不落缓存**的硬约束，不能省。

**api_base 三种路径（选其一）**：
1. 临时隧道（当前）：`https://father-starsmerchant-bizarre-upcoming.trycloudflare.com/v1`——仅联调，URL 每次重启变化。
2. 集群内（正式，阶段 4 后）：`http://confidential-adapter.litellm.svc.cluster.local:8080/v1`。
3. 公司内网域名/负载均衡（如需长期暴露 VM，登记专用域名）。

**禁止**：不要给该模型配 fallback、`model_group_alias`、隐式别名，也不要让它失败时自动切到普通模型（fail-closed）。

## 3. 字段兼容性校验（以现场版本为准）

| 字段 | 含义 | 说明 |
|---|---|---|
| `model: openai/<code>` | 走 OpenAI-compatible 路径 | 官方 `openai-proxy` 提供 OpenAI 兼容接口 |
| `api_base` | Adapter 端点 | 见第 2 节二选一 |
| `api_key: os.environ/...` | 从环境变量读 key | 形态 A 占位即可 |
| `timeout: 300` | 单次请求超时 | 推理耗时长，给足 |
| `max_retries: 0` / `num_retries: 0` | 关闭自动重试 | 新/老版本字段都写，防重复计费 |
| `cache: false` | 关闭响应缓存 | 明文不落缓存 |

> 若公司 LiteLLM 版本较老，`cache` / `max_retries` 字段可能不识别：删除不识别字段即可，但必须确保**不开启重试、不开启缓存**（可用 `litellm_settings.num_retries: 0` 全局兜底）。

## 4. 验证清单（2026-09-04 已执行结果）

| # | 场景 | 结果 | 证据 |
|---|---|---|---|
| 1 | 模型目录 `/v1/models` 含 `deepseek-v4-confidential` | ✅ 通过 | 返回含该 id（连同原有 `DeepSeek-R`、`qwen3-max`） |
| 2 | 非流式 `stream=false` | ✅ 通过 | `content=CONFIDENTIAL_OK`，`finish_reason=stop`，`model=deepseek-v4-confidential`，usage 正确 |
| 3 | SSE `stream=true` | ✅ 通过 | `1→2→3→4→5` 逐块，`finish_reason=stop`，`[DONE]` 结束 |
| 4 | 零重试对账（三层调用计数=1） | ✅ 通过 | 响应头 `X-Litellm-Attempted-Retries: 0`、`X-Litellm-Attempted-Fallbacks: 0`；Adapter 日志增量 `request started/finished/mapped` 各 +1，单请求仅一次上游映射，无重试 |
| 5 | 无降级（Adapter 不可用不切普通模型） | ✅ 通过（附 ⚠️） | 停 VM Adapter 后 aihub **未 fallback 到 `DeepSeek-R`/`qwen3-max`**；但隧道源站停机时 cloudflared 表现为挂起（HTTP 000），aihub 请求长时间挂起而非快速失败，见下方 ⚠️ |
| 6 | 明文泄漏扫描（canary 不入日志/缓存） | ✅ 通过 | canary `CANARY-7f3a9c2e841d` 在 Adapter 日志中不存在；透明度报告仅含 attestation 元数据（request_id/model/status/签名/公钥），无 prompt/completion/canary |

> **6/6 全部通过**。阶段 5 主链路 + fail-closed + 机密性专项均验证完毕。
>
> **⚠️ 清单 5 的补充发现（快速失败缺失）**：当前 `api_base` 走 Cloudflare Quick Tunnel。当源站（VM Adapter）停机时，cloudflared 并不返回 502/503，而是让连接挂起，因此 aihub 请求既**不降级**（正确，符合 fail-closed）也**不快速报错**（表现为长时间挂起，实测 >120s 未返回、`curl` 收到 `HTTP 000`）。这是隧道临时方案的固有行为，**不影响 fail-closed 结论**，但会拖慢故障暴露。生产切 K8s ClusterIP 后，Adapter 停机应表现为 `connection refused` → LiteLLM 快速返回错误。
>
> **关于 `max_retries`/`cache` 字段**：本次实测响应头已确认 `X-Litellm-Attempted-Retries: 0`、`X-Litellm-Attempted-Fallbacks: 0`，即当前即使未显式设 `max_retries`，LiteLLM 也未做自动重试；但仍建议在配置层显式锁死 `max_retries=0`/`cache=false` 以防未来版本或他人误改，作为静态护栏。

## 5. 已产出文件

- `litellm/company-merge-fragment.yaml`：等价 YAML 配置（本指南的 admin UI 填法对应的 config 形式，供 GitOps/版本化参考）。
- `litellm/config.yaml`：集群内 ClusterIP 版本参考（阶段 4 完成后用）。
- `litellm/config-vm.yaml`：Docker-first 直连 VM 版本参考。
- `scripts/vm/05-litellm-recon.sh`：litellm 容器现状探查脚本（本阶段已不用于公司 LiteLLM，保留备用）。

## 6. 隧道操作（临时联调）

- 启动：`cloudflared.exe tunnel --url http://192.168.200.128:18080 --no-autoupdate`（`.tools/cloudflared.exe`）。
- 输出里 `https://*.trycloudflare.com` 即临时公网地址；**每次启动会变**，需同步更新 LiteLLM 的 `api_base`。
- 停止：结束该进程即可（公网立即断开）。
- ⚠️ 联调结束务必关闭，避免持有 DashScope Key 的计费端点长期暴露公网。
