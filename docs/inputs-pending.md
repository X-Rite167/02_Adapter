# 待提供参数统一清单（占位保留）

> 状态：**全部待提供**——最后统一提供，当前不阻塞文档与脚本产出。  
> **统一填写入口：仓库根目录 `.env`**（已被 `.gitignore` 排除，禁止入库；填写后本清单状态需同步勾选）。  
> 原则：本清单是唯一凭据/参数入口；任何文档、脚本不得另行散落新的待填项。  
> 安全：真实值**禁止**提交 Git、禁止写入 Deployment YAML、ConfigMap、镜像层；生产环境统一通过 K8s Secret 注入，本地 POC 通过 `.env` 注入。

## 1. 本地 POC 所需（执行 `scripts/poc/01-local-sdk-poc.ps1` 时提供）

| 占位符 | 含义 | 提供方式 | 状态 |
|---|---|---|---|
| `<DASHSCOPE_API_KEY>` | 百炼 API Key（sk-xxx） | 环境变量，不入库 | ✅ 已提供（.env） |
| `<WorkspaceId>` | 机密推理 Workspace ID | 参数传入 | ✅ 已提供（.env） |
| `<model-code>` | 已部署模型 code（如 `cmaas-deepseek-v4-flash-0731`） | 参数传入 | ✅ 已提供（.env） |
| `<CMAAS_ENDPOINT>` | `https://<WorkspaceId>.cn-beijing.maas.aliyuncs.com/api/v1/services` | 由 WorkspaceId 推导，可选显式提供 | ✅ 已按 WorkspaceId 自动推导并连通 |

## 2. 构建与供应链冻结所需（阶段 1 前）

| 占位符 | 含义 | 状态 |
|---|---|---|
| `<SDK_COMMIT_SHA>` | `dashscope-confidential-maas` 固定 commit（能力矩阵基线） | ✅ POC 已锁定 tag v0.3.1 + tag 对象 SHA + tarball SHA256 + module Sum（见能力矩阵）；commit SHA 待阶段 1 构建机 `git ls-remote` 补取 |
| `<GO_BUILDER_DIGEST>` | Go 1.24.x 构建镜像 digest | ⬜ 待提供 |
| `<IMAGE_REGISTRY>` | 内部镜像仓库地址 | ⬜ 待提供 |

## 3. 集群部署所需（阶段 4 前）

| 占位符 | 含义 | 状态 |
|---|---|---|
| `<ADAPTER_API_KEY>` | LiteLLM → Adapter 的应用层密钥（形态 B 必需） | ⬜ 待提供 |
| `<NAMESPACE>` | 目标 namespace（默认 `litellm`） | ⬜ 待提供 |
| `<STORAGE_CLASS>` | 报告持久化 PVC 的 StorageClass | ⬜ 待提供 |
| `<PCCS_URL>` | TDX collateral 服务地址（如需自定义） | ⬜ 待提供 |

## 3.5 虚拟机 Docker 验证所需（阶段 0 集群 POC）

| 占位符 | 含义 | 状态 |
|---|---|---|
| `VM_HOST` | 虚拟机 IP（SSH 部署目标） | ⬜ 待提供 |
| `VM_USER` | SSH 用户名 | ⬜ 待提供 |
| `VM_PORT` | SSH 端口（默认 22） | ⬜ 待提供 |
| `VM_REMOTE_DIR` | 虚拟机上的项目目录（默认 `~/02_Adapter`） | ⬜ 待提供 |

## 4. 产品/容量/合规所需（Pilot 准入前）

| 占位符 | 含义 | 状态 |
|---|---|---|
| `<RPM>` / `<TPM>` | 机密部署限流规格 | ⬜ 待提供 |
| `<PILOT_TENANTS>` | Pilot 白名单租户与配额 | ⬜ 待提供 |
| `<PRICING_SOURCE>` | 官方目录价确认来源（忙/闲时、缓存命中） | ⬜ 待提供 |
| `<LEGAL_SIGN_OFF>` | 定向邀请 + 特别规则签署证明 | ⬜ 待提供 |
| `<CONTENT_COMPLIANCE_OWNER>` | 内容审核与 AI 生成标识责任方 | ⬜ 待提供 |

## 5. 提供时机约定

- **最后统一提供**，一次性补齐本清单并勾选状态。
- 提供后同步回填：
  - `docs/capability-matrix.md`（SDK commit 基线）
  - `docs/adr/001-cmaas-adapter-shape.md`（POC 证据表）
  - `docs/model-catalog.md`（模型目录字段）
  - `docs/stage0-validation-report.md`（解除阻塞项）
