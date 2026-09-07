# 模型目录与命名决策（阶段 0 冻结版）

> 责任人：产品专家（冻结）、架构师（会签）  
> 冻结日期：2026-09-03

## 1. 命名规则（冻结）

1. 公开逻辑模型名必须显式含 Confidential 语义，格式：`<base>-confidential`。
   - 示例：`deepseek-v4-confidential`（对应 `cmaas-deepseek-v4-flash-0731`）。
2. 普通（非 TEE）模型必须使用**不同的公开模型名**，由调用方发起新请求显式选择；不提供隐式别名切换。
3. LiteLLM 将逻辑模型名**唯一映射**到一个 CMAAS Adapter 后端模型；Adapter 只接受白名单内的后端模型，不接受请求体动态切换。
4. 业务侧不可见：`WorkspaceId`、后端模型 code、Adapter key、DashScope key。

## 2. 模型目录（模板）

| 字段 | 值（示例） |
|---|---|
| logical_name | `deepseek-v4-confidential` |
| provider | `cmaas` |
| backend_model | `<model-code>`（占位，见 `docs/inputs-pending.md`） |
| capability | Chat Completions / SSE / tools ✅实测（2026-09-03）；reasoning 字段被接受但 flash 模型不产出 `reasoning_content`（见能力矩阵） |
| context | `<待提供>`（占位，见 `docs/inputs-pending.md`） |
| RPM / TPM | `<RPM>` / `<TPM>`（占位，见 `docs/inputs-pending.md`） |
| 计费方式 | Token 目录价（输入/输出/隐式缓存命中；忙时 8:00–22:00 北京时间） |
| effective_at | `<部署生效日期，最后统一提供>` |
| source | 百炼控制台部署详情 |
| attestation | fail-closed，无普通模型 fallback |

> 每次变更必须更新目录版本并绑定验证日期。

## 3. 降级规则（冻结）

- 证明、PCCS、透明日志、CMAAS、代理或配额任一失败 → 返回明确错误。
- **绝不**自动切换到非 TEE 模型；降级只能是限流或明确失败。

## 4. 待产品回填（不阻塞阶段 0 技术 POC）

以下各项已占位保留，**最后统一提供**（跟踪见 `docs/inputs-pending.md`）：

- [ ] `<PRICING_SOURCE>`：官方目录价确认来源（`cmaas-deepseek-v4-flash-0731` 忙时输入 6 / 输出 18 / 缓存命中 0.6 元每百万 token；闲时 3 / 9 / 0.3，以官方目录价为准）。
- [ ] `<PILOT_TENANTS>`：Pilot 白名单租户清单与配额。
- [ ] `<LEGAL_SIGN_OFF>` / `<CONTENT_COMPLIANCE_OWNER>`：内容审核与 AI 生成内容标识的责任系统确认（阶段 -1 门禁）。
