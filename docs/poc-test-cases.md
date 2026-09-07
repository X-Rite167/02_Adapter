# 阶段 0 POC 测试用例（测试专家）

> 用途：为 `docs/adr/001-cmaas-adapter-shape.md` 的 POC-1 ~ POC-5 提供可执行用例。  
> 证据目录：`.poc/evidence/<run-id>/`，每个用例输出到独立文件，文件名即用例编号。  
> 前置：`01-local-sdk-poc.ps1` 已通过；LiteLLM 测试实例可访问；代理进程已在目标环境运行。

## POC-1 协议兼容（后端执行，测试专家记录证据）

| 用例 | 命令要点 | 断言 |
|---|---|---|
| 1.1 非流式 Chat | `curl /v1/chat/completions`，`stream:false` | 200；schema 含 `id/object/created/model/choices[].message/usage`；`finish_reason=stop`；usage 三项齐全 |
| 1.2 流式 SSE | `curl -N`，`stream:true` | `content-type: text/event-stream`；多 chunk 均 `object=chat.completion.chunk`；以 `data: [DONE]` 收尾 |
| 1.3 usage 透传 | `stream_options.include_usage:true` | 末尾出现 `choices:[]` 且带 usage 的 chunk |
| 1.4 tools | 请求带 `tools` 定义，prompt 引导调用 | 返回 `tool_calls`；流式下 arguments 分片完整；第二轮 `role=tool` 可继续 |
| 1.5 reasoning | 按模型设置 `thinking_budget` | `reasoning_content` 字段按模型能力出现/不出现，不报错 |
| 1.6 参数边界 | `temperature=-1`、`top_p=0` | 400 且错误体为 OpenAI 风格 `{error:{...}}` |

## POC-2 拒绝行为（测试专家）

| 用例 | 请求 | 断言 |
|---|---|---|
| 2.1 未知模型 | `model: not-in-whitelist` | 4xx；确认 CMAAS 侧计费/调用记录为 0 次 |
| 2.2 Responses API | `POST /v1/responses` | 404 |
| 2.3 多模态 | message content 为数组含 `image_url` | 400，不静默丢弃 |
| 2.4 显式缓存 | 带 `cache_control` 或缓存相关参数 | 400（或按官方代理实测记录实际行为并回填 ADR） |
| 2.5 联网搜索 | `tools:[{type:web_search}]` 或等价 | 400 |
| 2.6 未声明顶层字段 | 如 `user:"x"`、`metadata:{...}` | 记录实际行为：静默忽略则标记为形态 B 触发缺口 |
| 2.7 非法 JSON / 超大 body | 畸形 body、> 上限 body | 400，错误体稳定 |

## POC-3 调用方限制（网络专家，复用 `02-cluster-network-check.ps1`）

| 用例 | 断言 |
|---|---|
| 3.1 CNI 识别 | 明确 Cilium / Calico / 其他，回填 FQDN policy 能力 |
| 3.2 手段验证 | NetworkPolicy / FQDN policy / mesh 授权 / egress gateway 至少一种实测生效 |
| 3.3 最小访问 | 仅 LiteLLM selector 可达 Adapter:8080；其他 selector 不可达 |
| 3.4 出口 | Adapter 仅可达 CMAAS:443 + PCS/PCCS/Rekor/DNS，公网任意 443 不可达 |

## POC-4 取消传播与零重试（测试专家 + 后端）

| 用例 | 操作 | 断言 |
|---|---|---|
| 4.1 客户端取消 | 流式中途 `Ctrl+C` / 关闭连接 | 上游连接及时关闭；三层调用次数恒为 1 |
| 4.2 连接前失败 | 代理未启动时发起请求 | LiteLLM 报错；代理 0 次调用；LiteLLM `max_retries:0` 下无重试 |
| 4.3 已发送无响应 | 模拟上游挂起后超时 | 各层尝试次数为 1，无重复计费 |
| 4.4 429 / 5xx | 压测触发限流或注入故障 | 429 映射为 `rate_limit_error`；LiteLLM 不自动重试 |

## POC-5 滚动更新与长 SSE（后端 + 测试）

| 用例 | 操作 | 断言 |
|---|---|---|
| 5.1 SIGTERM 行为 | 长流进行中 `kubectl rollout restart` / 删 Pod | 实测：流是否完成、是否报错、`terminationGracePeriodSeconds` 是否足够；**只记录事实，不宣称排空能力** |
| 5.2 报告文件 | 流式与非流式各一次后检查报告目录 | `reports-*.jsonl` 与 `attestation-materials/` 均生成；`--no-prompt-in-transparency-report` 下报告无明文 prompt |
| 5.3 cmaas-audit | 对报告目录执行 `cmaas-audit` | 校验通过且退出码为 0 |

## 实测结果记录（2026-09-03，tag v0.3.1）

| 用例 | 结果 | 证据 |
|---|---|---|
| 1.1 非流式 Chat | ✅ 200，标准 schema + usage | `.poc/proxy-nonstream.log` |
| 1.2 流式 SSE | ✅ chunk 序列 + usage chunk + `[DONE]` | `.poc/proxy-stream.log` |
| 1.4 tools | ✅ `tool_calls` + `finish_reason=tool_calls` | `.poc/evidence/20260903-161957/tools.log` |
| 1.5 reasoning | ⚠️ `thinking_budget` 接受且 200；flash 不产出 `reasoning_content`（`reasoning_tokens=0`） | `.poc/evidence/20260903-161957/reasoning.log` |
| 2.1 未知模型 | ✅ HTTP 400 `model_not_found` | `.poc/proxy-unknown-model.log` |
| 2.3 多模态 | ✅ HTTP 400 `invalid_parameter_error` | `.poc/evidence/20260903-161957/multimodal.log` |
| 2.6 未声明顶层字段 | ⚠️ **静默忽略**（`user` 字段→200 成功）——形态 B 触发点，需产品确认 | `.poc/evidence/20260903-161957/unknown-field.log` |

> 环境注意（PowerShell 5.1）：JSON body 经 `--data-binary @file` 传递；原生命令 stderr 需重定向文件；脚本需 UTF-8 BOM。

## 证据归档要求

- 所有用例输出重定向到 `.poc/evidence/<run-id>/<用例编号>.log`。
- 用例 2.6 的结果决定 ADR-001 形态：若官方代理静默忽略未声明字段，且该缺口被冻结为硬需求，则形态 B 成立。
- 任何失败必须重跑并记录；证据缺失即「阶段 0 未完成」，不进入阶段 1。
