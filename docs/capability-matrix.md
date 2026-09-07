# MVP 能力矩阵（阶段 0 冻结版）

> 责任人：架构师（冻结）、产品专家（会签）  
> 冻结日期：2026-09-03  
> 绑定基线：`github.com/dashscope/dashscope-confidential-maas` @ **tag `v0.3.1`（2026-08-27 发布，Go 1.24.0）**  
> 校验锚点：tag 对象 SHA `8038182947c90ddc2fef1f292bd15df1fdef556c`；完整源码 tarball SHA256 `6200BAD51D96F9968598711D59E87FEC62E1E0DA3084F21876673EF484D67B60`；Go module Sum `h1:mR+kUEVvCVt/GmxNioJ/s5y9Mq3p2uoTLxSfZE0pyJU=`  
> 验证日期：2026-09-03（本地 POC 实测）；commit SHA 待阶段 1 构建机 `git ls-remote` 补取后回填  
> 模型：`cmaas-deepseek-v4-flash-0731`（实际部署 code，已通过直连验证）

## 1. 契约说明

1. 本矩阵只描述 **LiteLLM → CMAAS Adapter** 的接口契约；业务应用只看到 LiteLLM 的逻辑模型名。
2. 「支持」表示 Pilot 承诺可依赖；「不支持」表示 Adapter 必须**显式拒绝**（稳定 4xx，不静默降级、不静默忽略）。
3. 「验证中」表示 POC 阶段必须实测并回填证据，未回填前不得对外承诺。
4. 任何契约变更必须更新本矩阵版本、SDK commit SHA 与验证日期。

## 2. 能力矩阵

| 能力 | Pilot 契约 | 拒绝方式（如不支持） | 证据来源 |
|---|---|---|---|
| `POST /v1/chat/completions`（纯文本） | 支持 | — | ADR POC-1 |
| 非流式响应 | 支持 | — | ADR POC-1 |
| 流式 SSE（含 `[DONE]`） | 支持 | — | ADR POC-1 / POC-5 |
| `temperature` / `top_p` / `max_tokens` / `stop` / `seed` / `n=1` | 支持（取值范围以官方 `validation.go` 为准） | 非法取值 → 400 | ADR POC-1 |
| `stream_options.include_usage` | 支持 | — | ADR POC-1 |
| tools / function calling | 支持；Adapter 只产生 tool call，工具由调用方执行 | — | ✅ 已实测（2026-09-03）：`tool_calls` + `finish_reason=tool_calls` |
| `reasoning_content` / `thinking_budget` / `enable_thinking` | `thinking_budget` 被接受且不报错；但 `cmaas-deepseek-v4-flash-0731` **不产生** `reasoning_content`（`reasoning_tokens=0`），不对外承诺 reasoning 能力 | 无 | ✅ 已实测（2026-09-03）：接受但无产出 |
| `GET /v1/models`（官方代理） | 仅 Adapter 内部就绪检查；**不作为业务模型目录** | — | ADR POC-2 |
| `POST /v1/completions` | 不支持（不纳入 Pilot） | 404 / 明确错误 | ADR POC-2 |
| Responses API | 不支持 | 404 | ADR POC-2 |
| 图片 / 音频 / 视频等多模态 | 不支持 | 400 | ✅ 已实测（2026-09-03）：image URL 校验失败返回 400 `invalid_parameter_error` |
| 显式缓存 / `cache_control` | 不支持 | 400 | ADR POC-2 |
| 内置联网搜索 | 不支持 | 400 | ADR POC-2 |
| 未知 endpoint | 不支持 | 404 | ADR POC-2 |
| 未知模型名（不在白名单） | 不支持 | 400，上游 0 次调用 | ✅ 已实测（2026-09-03）：HTTP 400 `model_not_found` |
| 未声明顶层字段 | 能确定不受支持时返回稳定 4xx；**不得静默忽略** | 400 | ⚠️ 已实测（2026-09-03）：官方代理**静默忽略**（`user` 字段→200）——**形态 B 触发点**，见 ADR-001 |

## 3. 形态决策输入（供 ADR-001）

| 验证项 | 判定标准 | 当前状态 |
|---|---|---|
| POC-1 协议兼容 | 非流式/SSE/tools/reasoning 全部通过 | ✅ 非流式/SSE/usage 已验（2026-09-03 本地）；tools/reasoning 待补 |
| POC-2 拒绝行为 | 未知字段/模型/endpoint 的拒绝契约满足矩阵 | ✅ 未知模型→400 `model_not_found` 已验（本地预演）；其余待集群验证 |
| POC-3 网络可达性 | 存在可执行的调用方限制手段（NetworkPolicy/FQDN policy/mesh 授权/egress gateway） | 待在线执行 |
| POC-4 取消传播 | 客户端取消时三层（业务→LiteLLM→Adapter→CMAAS）调用次数恒为 1 | 待在线执行 |
| POC-5 滚动更新 | SIGTERM/长 SSE 排空行为实测，且不宣称未经验证的排空能力 | 待在线执行 |

## 4. 会签

| 角色 | 结论 | 签名（具名） |
|---|---|---|
| 架构师 | 契约已冻结 | 待签名 |
| 产品专家 | 同意 Pilot 范围 | 待签名 |
| 测试专家 | 用例已覆盖矩阵全部拒绝项 | 待签名 |
| 安全/TEE 专家 | fail-closed 原则已嵌入契约 | 待签名 |

> 门禁：上表中任一「待在线执行」项在 POC 前不得转换为「支持/承诺」。
