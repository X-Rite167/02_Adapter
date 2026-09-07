# 阶段 0 最终校验报告

> 校验人：测试专家（技术完整性）、产品专家（契约与门禁）  
> 校验日期：2026-09-03  
> 校验对象：阶段 0「冻结 MVP 契约和 ADR」的全部产出物  
> 校验原则：fail-closed——任何证据缺失不得判为通过。

## 1. 产出物清单

| 产出物 | 责任角色 | 状态 |
|---|---|---|
| `docs/capability-matrix.md` | 架构师 | ✅ 已落盘 |
| `docs/adr/001-cmaas-adapter-shape.md` | 架构师 | ✅ 已落盘（Proposed，待证据定稿） |
| `docs/model-catalog.md` | 产品专家 | ✅ 已落盘 |
| `docs/poc-test-cases.md` | 测试专家 | ✅ 已落盘 |
| `scripts/poc/01-local-sdk-poc.ps1` | 后端专家 | ✅ 已落盘 |
| `scripts/poc/02-cluster-network-check.ps1` | 网络专家 | ✅ 已落盘 |

## 2. 测试专家校验

### 2.1 通过项

1. 能力矩阵中每一项「不支持」都绑定了拒绝方式（4xx）与证据来源（POC 用例编号）。
2. POC 用例覆盖了 ADR-001 要求的全部五个验证项，且与能力矩阵交叉引用闭环。
3. 用例 2.6（未声明字段的实际行为）被显式标注为**形态决策的触发点**，与 ADR 决策规则一致。
4. 零重试、取消传播、报告审计、滚动排空均有对应用例（POC-4、POC-5），未遗漏。
5. 证据归档路径与命名约定已冻结（`.poc/evidence/<run-id>/<用例编号>.log`）。

### 2.2 阻塞项（证据缺失）

| 项 | 说明 | 影响 |
|---|---|---|
| B1 | 本地+虚拟机 Docker 验证全部完成：非流式/SSE/usage/tools/多模态/未知模型/断连取消/重启恢复均已验；仅剩 K8s 侧 POC-3（NetworkPolicy）与 POC-5 真实滚动更新 | ADR-001 形态待产品确认（缺口 1/2） |
| B2 | ~~SDK commit SHA 未锁定~~ **已解除**：基线锁定 tag v0.3.1 + tag 对象 SHA `80381829...` + tarball SHA256 `6200BAD5...` + module Sum（2026-09-03 实测） | 契约基线成立 |
| B3 | ~~reasoning 契约验证中~~ **已解除**：实测 `thinking_budget` 被接受但 flash 模型不产出 `reasoning_content`（`reasoning_tokens=0`），契约已明确为「不对外承诺 reasoning」 | 不再阻塞 |

### 2.3 测试专家结论

**阶段 0 技术侧：NOT PASS（集群证据阻塞）。** 本地 POC 全部通过（远程证明 Verified/TDX、非流式、SSE、usage、tools、未知模型 400、多模态 400）；已实测官方代理对未知顶层字段**静默忽略**（形态 B 触发点）。剩余集群侧 POC-3/4/5 与形态决策（待产品确认缺口 1/2）在 LiteLLM 测试实例就绪后执行，完成前不得进入阶段 1。

## 3. 产品专家校验

### 3.1 通过项

1. 命名规则已冻结：`<base>-confidential`，普通模型不得复用同名，无隐式别名切换。
2. 降级规则明确：任何失败 fail-closed，绝不自动切换非 TEE 模型。
3. 业务不可见项已列出：`WorkspaceId`、后端 code、Adapter key、DashScope key。
4. 模型目录含成本关键字段（忙/闲时、缓存命中计费），并要求 `effective_at` 与验证日期绑定。

### 3.2 待产品侧回填（不阻塞技术 POC，但阻塞 Pilot 准入）

| 项 | 说明 |
|---|---|
| P1 | 模型目录中 RPM/TPM、context、生效日期未回填 |
| P2 | Pilot 白名单租户清单与配额未确认 |
| P3 | 阶段 -1 门禁（定向邀请、特别规则签署、内容审核责任系统）需产品/法务确认 |
| P4 | 忙闲时价格录入目录（文档中为示例值，需以官方目录价为准） |

### 3.3 产品专家结论

**阶段 0 产品侧：CONDITIONAL PASS。** 契约与命名冻结完成；P1–P4 必须在 Pilot 准入评审前关闭。

## 4. 最终判定（双专家会签）

| 判定项 | 结论 |
|---|---|
| 阶段 0 文档与脚本产出 | ✅ 完成 |
| 阶段 0 本地 POC 证据 | ✅ 完成：SDK 构建、远程证明 Verified(TDX)、非流式、SSE、usage、tools、拒绝行为 |
| 阶段 0 虚拟机 Docker 验证 | ✅ 完成：镜像构建（SHA256 校验）、端到端、断连取消（context canceled）、重启恢复、透明度报告落盘（2026-09-03） |
| 阶段 0 集群 K8s 证据 | ⏸ 遗留：POC-3（NetworkPolicy）、POC-5（真实滚动更新）转阶段 2 前条件 |
| 阶段 0 形态决策 | ✅ **已关闭（2026-09-03）**：形态 A 定稿，缺口由 NetworkPolicy 兜底（见 ADR-001） |
| **阶段 0 总判定** | **CONDITIONAL PASS（附遗留条件收口）** |

### 4.1 收口条件（fail-closed）

1. ✅ **C1（形态决策）已关闭（2026-09-03）**：产品确认采用形态 A（纯官方代理）；缺口 1（静默忽略）接受，缺口 2（无鉴权）由 NetworkPolicy/default-deny 兜底；薄桥仅作为集群无网络层手段时的兜底插件。见 `docs/adr/001-cmaas-adapter-shape.md`（已定稿）。
2. **C2（K8s 验证）**：Adapter 部署进 kite 平台前，必须完成 POC-3（调用方限制手段实测）与 POC-5（真实滚动更新）；未完成不得进入生产部署。
3. 任一条件到期未满足，阶段 0 判定回退为 NOT PASS。
| 阶段 0 产品准入前置 | ⚠️ 待回填（P1–P4） |
| **阶段 0 总判定** | **NOT PASS（集群证据阻塞），不得进入阶段 1** |

## 5. 解除阻塞的最小行动清单（按顺序）

1. ✅ **已完成**：凭据已提供（`.env`），本地 POC 已执行并全部通过（构建、直连、远程证明、非流式、SSE、usage、未知模型 400）。
2. ✅ **已完成**：基线锁定 tag v0.3.1（tag 对象 SHA + tarball SHA256 + module Sum），回填能力矩阵与 ADR 证据表。
3. ✅ **已完成**：本地 tools/reasoning 验证（tools ✅；`thinking_budget` 接受但不产出 reasoning；未知字段静默忽略；多模态 400），证据在 `.poc/evidence/20260903-161957/`。
4. ✅ **已完成（虚拟机 Docker）**：POC-4 断连取消（`context canceled` 验证）与 POC-5 近似（`docker restart` 恢复 + 透明度报告落盘）；发现并修复报告目录权限缺陷。
5. ⬜ **遗留 C2**：K8s（kite 平台）就绪后，执行 POC-3（NetworkPolicy/调用方限制）与 POC-5 真实滚动更新；LiteLLM `api_base` 指向 Adapter（虚拟机 IP:18080 或 K8s ClusterIP）。
6. ✅ **已完成 C1**：形态 A 定稿（2026-09-03），ADR-001 状态 Approved。剩余仅 C2（K8s POC-3/5，部署进 kite 平台前完成）。
6. ⬜ 重新提交双专家校验，更新本报告判定；通过后进入阶段 1（阶段 1 构建机补取 commit SHA）。
