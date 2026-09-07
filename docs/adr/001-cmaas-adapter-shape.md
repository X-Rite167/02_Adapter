# ADR-001：CMAAS Adapter 形态决策（A：纯官方代理 / B：薄桥）

> 状态：**Approved（形态 A 定稿）**  
> 日期：2026-09-03  
> 决策人：架构师 / 产品（用户确认）  
> 会签：后端、测试、网络、安全

## 1. 背景

官方 `dashscope-confidential-maas` 提供预编译产物 `openai-proxy`（形态 A）。
用户能力约束：不维护 Go 代码；未来可能有其他平台 SDK 加入；透明度报告需要持久化。
据此，**其他平台必须部署独立 Adapter 工作负载**（已在总文档 0.1 冻结），本 ADR 只决定 CMAAS 这一个 Adapter 的形态。

> 参数与凭据来源：统一见 `docs/inputs-pending.md`（最后统一提供）；本 ADR 证据表中的「待回填」为 POC 执行结果，不属于待提供参数。

## 2. 候选方案

### 形态 A：LiteLLM → ClusterIP:8080 → openai-proxy → CMAAS
- 优点：明文处理面、延迟、故障点最少；零新增代码。
- 风险：官方代理对未声明字段**静默忽略**（`forwardedChatFields` 白名单之外的字段被丢弃）；
  无应用层鉴权；SIGTERM 排空能力未实测。

### 形态 B：LiteLLM → 薄桥(:8000, 仅 Python FastAPI) → openai-proxy(127.0.0.1:8080) → CMAAS
- 薄桥只补已确认缺口：应用层鉴权、严格字段拒绝、错误归一化、并发上限、取消传播。
- 明确禁止：跨平台二次路由、缓存、自动重试、明文日志。

## 3. 决策规则（fail-closed）

- 若 POC-1 至 POC-5 在**不需要新增进程**的前提下全部满足 → 选形态 A。
- 任一验证项出现「必须由额外进程才能满足的契约缺口」→ 选形态 B，并在本 ADR 逐项写明薄桥存在的理由。
- 薄桥不得演变为新的业务路由层；新增平台走独立 Adapter 工作负载，不在薄桥内扩展。

### 3.1 已实测的缺口（2026-09-03）

- **缺口 1（可能触发形态 B）**：官方代理对未声明顶层字段**静默忽略**（实测 `user` 字段 200 通过）。若「显式拒绝不支持参数」为硬需求，形态 B 成立；若可接受静默忽略，形态 A 仍可成立。
- **缺口 2**：官方代理无应用层鉴权（`ADAPTER_API_KEY` 需求）——需 NetworkPolicy/mesh 授权兜底，或薄桥补鉴权。

## 4. POC 证据表（五专家分项执行，回填后本 ADR 方可定稿）

| 编号 | 验证项 | 执行人 | 通过标准 | 证据（日期/commit/结果文件） |
|---|---|---|---|---|
| POC-1 | 协议兼容（非流式/SSE/tools/reasoning/usage） | 后端 | 全部符合能力矩阵 | ✅ 非流式/SSE/usage/tools 均通过（2026-09-03，tag v0.3.1）；reasoning：`thinking_budget` 被接受但 flash 模型不产出 `reasoning_content`（`.poc/evidence/20260903-161957/`） |
| POC-2 | 拒绝行为（未知字段/模型/endpoint） | 测试 | 稳定 4xx、上游 0 次 | ✅ 未知模型→400 `model_not_found`；多模态→400 `invalid_parameter_error`；⚠️ 未知顶层字段被**静默忽略**（200）——形态 B 触发点；未知 endpoint 待集群验证 |
| POC-3 | 调用方限制手段可行性 | 网络 | 至少一种手段经实测生效 | 待回填 |
| POC-4 | 取消传播与零重试 | 测试 | 三层调用次数恒为 1 | ✅ 虚拟机 Docker 验证（2026-09-03）：客户端断连后 Adapter 日志 `context canceled`，413ms 内终止；LiteLLM 层零重试待 K8s 实测 |
| POC-5 | SIGTERM/长 SSE 滚动排空 | 后端/测试 | 实测结果记录，不做未验证承诺 | ✅ 近似验证（虚拟机 `docker restart`）：6s 内恢复、重启后推理正常；真实 K8s 滚动更新待补 |

## 5. 结论（定稿）

- 形态选择：**形态 A（纯官方 openai-proxy）**，已由产品/用户确认（2026-09-03）。
- 缺口处置：
  - 缺口 1（未声明字段静默忽略）：接受。属契约严格性问题，不影响机密性。
  - 缺口 2（无应用层鉴权）：由 K8s 原生能力兜底——NetworkPolicy（仅 LiteLLM 白名单）+ namespace default-deny（见 `k8s/networkpolicy.yaml`）；若集群实测无网络层限制手段，再以独立 Deployment 引入薄桥（仅补鉴权，不改现有接口）。
- 薄桥触发条件（未来）：集群禁止 NetworkPolicy/无服务网格授权、且无法用 egress gateway 限制调用方。
- 生效日期：2026-09-03。
