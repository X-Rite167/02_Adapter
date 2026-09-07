# LiteLLM 对接阿里云 Confidential MaaS 落地指南

> 文档状态：五角色联合评审修订版  
> 修订日期：2026-09-03  
> 适用范围：北京地域、已获定向邀请并签署特别规则的 Confidential Chat Completions Pilot

## 0. 结论与不可违反的边界

### 0.1 推荐架构

```text
业务应用
  -> LiteLLM（唯一业务模型目录、鉴权、配额和路由层）
      -> CMAAS Adapter Service（一个后端模型一个独立工作负载）
          -> 阿里云 Confidential MaaS Endpoint
      -> 未来 Platform-X Adapter Service（独立工作负载）
      -> 其他 OpenAI-compatible Provider（可由 LiteLLM 直接连接）
```

- 不建设一个承载所有平台 SDK、密钥和依赖的 Python 总网关。
- LiteLLM 独占逻辑模型名、Provider 选择、权重和业务鉴权；Adapter 不做跨平台二次路由。
- 必须使用 SDK 或协议不标准的平台，分别部署独立 Adapter、ServiceAccount、Secret、容量和发布流程。
- 标识为 `confidential` 的模型在任何错误下都必须 fail closed，绝不自动切换到非 TEE 模型。
- 普通模型必须使用不同的公开模型名，由调用方发起新请求并显式选择。

### 0.2 CMAAS Adapter 的两种形态

先用 POC 决定，不把 Python/FastAPI 预设为必需组件。

**形态 A，默认优先验证：**

```text
LiteLLM -> ClusterIP:8080 -> openai-proxy 0.0.0.0:8080 -> CMAAS
```

适用于 NetworkPolicy/服务网格授权可以限制调用方，且 LiteLLM 与 `openai-proxy` 已能满足字段、错误和观测契约的场景。它的明文处理面、延迟和故障点最少。

**形态 B，仅在 POC 证明必要时采用：**

```text
LiteLLM -> ClusterIP:8080 -> CMAAS thin bridge 0.0.0.0:8000
                                  -> openai-proxy 127.0.0.1:8080 -> CMAAS
```

薄桥只处理已确认的缺口，例如应用层鉴权、严格字段拒绝、错误归一化、并发上限或请求取消传播；不做跨 Provider 路由。Service 的 `port: 8080` 必须映射到命名 `targetPort: gateway-http`（8000）。同 Pod 容器共享网络空间，两个进程不能同时绑定 8080。

### 0.3 机密性边界

- Prompt 和 completion 在业务应用、LiteLLM 以及 CMAAS 客户端代理中是明文。CMAAS 的应用层加密从官方 SDK/代理开始，不能宣称业务应用到 TEE 全链路都没有明文。
- 同 Pod 容器共享网络身份和 ServiceAccount 边界，不构成强安全隔离；NetworkPolicy 也不能隔离同 Pod 容器或 loopback 流量。
- 节点管理员、容器调试、core dump、APM/OTel 自动采集和日志系统属于必须受控的可信运维面。
- `CMAAS_ALLOW_ATTESTATION_FALLBACK=false` 必须显式设置并由准入策略锁定。
- `CMAAS_DEBUG=false` 必须显式设置；任何处理真实或敏感数据的环境都禁止启用。该值为 `true` 时代理可能记录完整明文请求和响应。
- CMAAS 不提供内容安全过滤。内容审核和 AI 生成内容标识必须在经批准的可信边界内实现；不得为审核目的擅自把明文发送给第三方。

## 1. 五角色评审结果

| 角色 | 阻断问题 | 修订结论 |
|---|---|---|
| 架构师 | 预编译产物假设错误、双重路由、端口冲突、跨 Provider 故障域过大 | 固定源码 commit 构建；LiteLLM 单一路由；每个平台独立 Adapter；FastAPI 改为 POC 后的可选薄桥 |
| 测试专家 | tools 能力判断错误、SSE/零重试不可证明、缺少统一验收入口 | 建立版本化能力矩阵和 `make acceptance`；覆盖任意 SSE 分块、取消、调用次数和报告对账 |
| CMAAS/TEE 专家 | 机密边界不清、普通模型 fallback、报告与证明依赖遗漏 | Confidential 永不降级；同时保存 JSONL 与 attestation materials；保护 PCCS/Rekor 信任链 |
| 产品经理 | 缺少准入、MVP、SLO、成本与责任门禁 | 第一阶段只做白名单 Pilot；不承诺外部 SLA；模型价格目录和 go/no-go 具名签字 |
| 网络专家 | FQDN 不能由标准 NetworkPolicy 表达、RWO 阻塞滚动、mesh 可能破坏 SSE/TLS | 使用经验证的 FQDN policy 或 egress gateway；StatefulSet/RWX 二选一；禁止 TLS inspection 和 HTTP retry |

## 2. 阶段 -1：商务、地域与合规准入

执行人：产品负责人、业务负责人、法务/合规、阿里云账号负责人。

1. 确认业务账号已获得 Confidential MaaS 定向邀请。
2. 确认 Workspace 和部署均位于当前支持的华北 2（北京）地域。
3. 完成《阿里云百炼机密推理服务特别规则》签署与内部合规审批。
4. 确认数据、透明度报告、备份和运维访问的地域边界。
5. 确认内容审核、违规处置、申诉、审计留痕和 AI 生成内容标识责任系统。

**门禁：** 任一项未完成，不进入生产排期。

## 3. 阶段 0：冻结 MVP 契约和 ADR

### 3.1 MVP 能力矩阵

能力矩阵必须绑定 SDK 完整 commit SHA、模型和验证日期，不以 `main` 分支行为作为长期承诺。

| 能力 | Pilot 契约 |
|---|---|
| `POST /v1/chat/completions` 文本 | 支持 |
| 非流式与 SSE | 支持 |
| tools/function calling | 支持；仅产生 tool call，工具由调用方执行 |
| reasoning | 按模型验证 `reasoning_content`、`thinking_budget`、`enable_thinking` |
| `GET /v1/models` | 仅内部能力/就绪检查；业务模型目录由 LiteLLM 提供 |
| `POST /v1/completions` | 不纳入 Pilot，除非单独验收 |
| Responses API | 不支持 |
| 图片、音频、视频等多模态 | 不支持 |
| 显式缓存/cache-control | 不支持 |
| 内置联网搜索 | 不支持 |
| 未声明 endpoint/字段 | 在能够确定不受支持时返回稳定 4xx，不静默降级 |

### 3.2 ADR-001：是否需要薄桥

完成以下 POC 后记录 ADR：

1. 验证 LiteLLM 到官方代理的非流式、SSE、tools、reasoning 和错误响应。
2. 验证未知字段、未知模型和不支持 endpoint 的实际行为。
3. 验证集群能否用 NetworkPolicy、Cilium/Calico FQDN policy、服务网格授权或 egress gateway 限制调用方。
4. 验证客户端取消是否传递到 CMAAS，三层调用次数是否始终为 1。
5. 验证代理在 Kubernetes SIGTERM、长 SSE 和滚动更新时的实际行为。仅增加 `terminationGracePeriodSeconds` 不等于已经排空。

若上述契约无需新增进程即可满足，采用形态 A；否则采用形态 B，并在 ADR 中逐项写明薄桥存在的理由。不得把薄桥扩展成新的业务路由层。

### 3.3 模型命名与降级

- 公开逻辑模型名必须显式含有 Confidential 语义，例如 `deepseek-v4-confidential`。
- LiteLLM 将逻辑模型映射到一个确定的 CMAAS Adapter 后端模型。
- Adapter 只允许配置的后端模型，不接受请求动态切换到其他模型。
- 证明、PCCS、透明日志、CMAAS、代理或配额失败时返回明确错误；不配置普通模型 fallback。

## 4. 阶段 1：固定官方源码和可复现构建

官方当前交付方式是从 `dashscope/dashscope-confidential-maas` 源码执行 `make openai-proxy` 和 `make cmaas-audit`，不能假定存在官方预编译镜像。

> **2026-09-03 本地 POC 实测事实（后端专家修订）：**
> - 基线已锁定 tag `v0.3.1`（2026-08-27），`go.mod` 要求 Go ≥ 1.24.0（实测 1.27.1 可用）。
> - `go install pkg@version` **不可用**：官方 go.mod 含 `replace ./pkg`，Go 禁止模块外安装含 replace 的模块。
> - Go module zip **不含 `pkg/` 子模块**（release 不完整），不能只依赖 module proxy 源码；必须下载**完整源码 tarball**（`codeload.github.com` 实测可达）。
> - 无 make/git 环境可用 `go build ./cmd/...` 等价构建（已实测三个 cmd 全部构建成功）。
> - 国内构建机网络实测：`github.com`/`go.dev` 不通；`codeload.github.com`、`goproxy.cn`、`mirrors.aliyun.com/golang/` 可达。依赖拉取用 `GOPROXY=https://goproxy.cn,direct`。
> - Windows PowerShell 5.1 已知坑：原生命令 stderr 会触发 NativeCommandError（EAP=Stop 时）、传参剥离 JSON 双引号（body 用 `--data-binary @file`）。

1. 记录官方仓库 URL、完整 commit SHA、源码归档 SHA256 和许可证（POC 已记录 tag 对象 SHA 与 tarball SHA256，commit SHA 于构建机 `git ls-remote` 补取）。
2. 使用固定 digest 的 Go 1.24.x builder，在多阶段 Docker build 中 checkout 指定 commit。
3. 执行官方 `make openai-proxy cmaas-audit`（或经验证等价的 `go build ./cmd/...`）；运行官方 `go test ./...`。
4. 最终运行镜像只复制必要二进制、CA 证书和运行时文件，使用非 root 用户与只读根文件系统。
5. 生成 SBOM、漏洞扫描报告、构建证明和最终镜像 digest；在 CI/admission 使用固定 identity/issuer 与 Sigstore bundle 验签。
6. 不从运行时网络下载二进制，也不使用浮动 tag 或 `main` 构建生产镜像。

**门禁：** 来源、commit、builder digest、测试结果、SBOM、产物 SHA256 和镜像签名均可追溯。

## 5. 阶段 2：实现 CMAAS Adapter

> **2026-09-03 落实状态（形态 A 定稿，见 ADR-001）**：5.1 全部参数已配置并验证生效——固定 `--model`、`--workers=2`、`--max-concurrency=4`、报告目录、`--no-prompt-in-transparency-report`、attestation fallback 与 DEBUG 均硬关闭、API key 仅代理容器持有。5.2 薄桥在形态 A 下**不适用**（仅当集群无网络层限制手段时作为兜底插件触发，届时再补实现）。

### 5.1 官方代理参数

- 每个工作负载固定一个 `--model`，必要时设置 `--served-model-name`。
- 显式设置 `--workers`，不得使用默认 32；从较小值开始压测。
- 显式设置 `--max-concurrency`，禁止无界并发和多层排队。
- 显式设置 `--transparency-report-dir=/var/lib/cmaas/reports`。
- 启用 `--no-prompt-in-transparency-report`；报告仍按敏感审计数据保护。
- 显式设置 `CMAAS_ALLOW_ATTESTATION_FALLBACK=false`、`CMAAS_DEBUG=false`。
- 只有官方代理容器获得 `DASHSCOPE_API_KEY`；薄桥和审计 Job 均不得获得该 Secret。

### 5.2 薄桥要求（仅形态 B）

1. 只暴露 `/v1/chat/completions`、`/health/live`、`/health/ready`；`/v1/models` 仅在需要时返回配置白名单。
2. 使用独立 Adapter key 或 mesh identity；支持新旧 key 重叠轮转，不把入站 Authorization 原样转发给代理。
3. 只做 CMAAS capability 校验、body 上限、并发控制、错误归一化和透明 SSE 转发。
4. 不缓存请求或响应，不自动重试，不记录 prompt、completion、tools 参数或 reasoning 内容。
5. SSE 必须逐块 flush、保持背压并在客户端断开后取消上游。
6. Headers 发出前可返回 OpenAI 风格 JSON 错误；流开始后的错误只能表现为无 `[DONE]` 的不完整流并记录关联 ID，不能改写 HTTP 状态。
7. `/health/live` 只检查自身；`/health/ready` 从 Pod 内访问代理 `GET /v1/models` 并确认目标模型。外部 CMAAS 深度检查使用独立 synthetic probe，不能让网络抖动摘除全部 Pod。

## 6. 阶段 3：透明度报告持久化和审计

> **2026-09-03 虚拟机 Docker 实测状态（形态 A）：**
> - 报告持久化验证通过：容器以非 root `cmaas` 运行，`/var/lib/cmaas/reports` 由 `mkdir -p` + `chown cmaas:cmaas` 授予写权限，JSONL（0600）与 `attestation-materials/`（0700）正常落盘，材质文件 4 个。
> - `cmaas-audit` 实测：`attestation verify` 对 6 条请求记录 **6/6 全部通过**；`transparency-log list` 返回真实 Rekor 条目（`rekor.sigstore.dev`，log index `2582842390`，含 inclusion proof），证明 SDK 已将证明写入 Sigstore 透明日志；`release dump` 返回 release manifest（`container.image.cmaas-runtime` sha256）。
> - 审计脚本 `scripts/vm/03-audit-reports.sh`：清单 → 逐请求 attestation verify → 逐请求 transparency-log list → `docker cp` 归档 + SHA256 manifest。**关键坑**：镜像 `ENTRYPOINT` 为 `openai-proxy`，所有审计命令必须加 `--entrypoint cmaas-audit` / `--entrypoint sh` 覆盖，否则会误执行代理并报 `endpoint flag is required`。
> - 归档产物：`/var/backups/cmaas-reports/20260903-173848/`（reports JSONL + attestation-materials + `manifest.sha256`）。

官方代理会在指定目录追加每日、进程级 `reports-YYYY-MM-DD-PID.jsonl`，并在 `attestation-materials/` 保存按内容哈希引用的证明材料。两者必须作为一个证据集合处理。

### 6.1 存储决策

默认使用 StatefulSet `volumeClaimTemplates` 为每个 Pod 提供独立加密 RWO PVC。一个模型一个 StatefulSet，Pilot 可从 1 个副本开始；需要生产可用性时至少验证 2 个副本。

可选方案是经评审的 RWX 存储或将关闭的报告归档至启用版本控制/Object Lock 的对象存储。普通 Deployment 共享一个 RWO PVC、`maxUnavailable=0` 和跨节点滚动不能同时作为默认方案。

### 6.2 报告规则

1. 代理直接写 `/var/lib/cmaas/reports`，不假设它自动创建 Pod/日期子目录。
2. 原始 JSONL、`attestation-materials` 和 SHA256 manifest 一起归档；归档过程不得修改原件。
3. 只处理已关闭的前一日文件；当天文件、活跃 PID 文件和未归档材料不得清理。
4. 集中审计从只读快照或对象存储运行 `cmaas-audit`；审计 ServiceAccount 不读取模型 API key。
5. `cmaas-audit` 的“离线”表示不再发起模型推理，不等于 air-gapped：`attestation verify` 会获取 TDX collateral，透明日志验证也可能获取 Rekor 公钥或状态。审计 Job 使用独立身份和最小出口策略，只放行经固定版本验证所需的 PCS/PCCS、Rekor/信任根；不得复用运行时 Pod 的宽泛出口权限。
6. 保存签名审计结果、checkpoint state 和失败指标；篡改、截断、材料缺失必须导致非零退出。
7. 保留期由特别规则、法务、隐私和审计要求共同确定，不预设 30 至 90 天。
8. 配置卷加密、备份恢复、访问审计、容量与 inode 告警。审计失败不得删除证据，但也必须有容量耗尽处置方案。
9. 按 request id 对账完成请求、JSONL 记录和材料；崩溃或未完成流可能没有完整报告，“无报告”不能证明“无请求”。

## 7. 阶段 4：Kubernetes 和网络部署

### 7.1 运行对象

- 每个 CMAAS 模型一个 StatefulSet、ClusterIP Service、ServiceAccount 和 Secret。
- `automountServiceAccountToken: false`；Pod ServiceAccount 不授予 `get/list/watch secrets`。
- 使用 Pod Security Restricted 基线：非 root、只读根文件系统、drop all capabilities、seccomp RuntimeDefault。
- 配置 startup/readiness/liveness probes、资源限制、PDB、拓扑分散和受控的滚动策略。
- 配置 checksum annotation 或版本化不可变 ConfigMap/Secret 触发 rollout；镜像和配置必须原子回滚。

### 7.2 NetworkPolicy

1. namespace 先配置 default-deny ingress/egress。
2. Adapter ingress 只允许 LiteLLM：`namespaceSelector` 与 `podSelector` 必须位于同一个 `from` 项中，表达 AND 而不是 OR。
3. DNS 同时允许 UDP/TCP 53，并按实际 CoreDNS 或 NodeLocal DNSCache 模式配置。
4. 标准 Kubernetes NetworkPolicy 不支持可靠的 FQDN 白名单。必须明确选择并验证：
   - Cilium/Calico 等 FQDN policy；或
   - HA egress gateway/firewall/CONNECT proxy，由其执行 FQDN/SNI allowlist。
5. 运行时依赖清单必须通过固定 SDK 版本的 DNS/flow log 实测冻结，至少评估：
   - `${WorkspaceId}.cn-beijing.maas.aliyuncs.com:443`；
   - TDX collateral 所需 PCS/PCCS，必要时批准 `PCCS_URL`；
   - SDK 在线透明日志验证所需 Rekor/信任根服务；
   - 企业代理和时间同步等实际依赖。

> **2026-09-03 虚拟机 Docker 实测冻结（tag v0.3.1，形态 A）：**
> - **推理路径**（openai-proxy live 请求，busybox `netstat` 采样）：只连接 `ws-la2jmsuqq2d1zfv2.cn-beijing.maas.aliyuncs.com:443` → `101.201.58.201`（阿里云 NLB）。**不连 Rekor/PCCS**。
> - **审计路径**（cmaas-audit `attestation verify`）：连接 `sgx-dcap-server.cn-hangzhou.aliyuncs.com:443` → `101.37.132.1`（另 `47.111.202.72`），用于拉取 PCK CRL / TDX collateral（默认 PCCS，二进制内嵌 `https://sgx-dcap-server.cn-hangzhou.aliyuncs.com/sgx/certification/v4/`）。
> - **审计路径**（cmaas-audit `transparency-log list`）：报告内嵌 `https://rekor.sigstore.dev` → `34.36.47.134`。
> - 二进制内另见 `wapi.trustedservices.intel.com`（Intel QE 备用端点，本次实测未建立连接）；`PCCS_URL` 环境变量可覆盖默认 collateral 服务。
> - 已回填 `k8s/networkpolicy.yaml` 注释。**注意推理与审计 egress 面不同**：审计 Job 需额外放行 PCCS + Rekor，运行时 Pod 仅需 CMAAS + DNS。
6. 构建期依赖（阶段 1 构建机）同样纳入清单：`codeload.github.com`（完整源码 tarball）、`goproxy.cn`（模块依赖）、`mirrors.aliyun.com/golang/`（Go 工具链）；这些域名在目标网络中的可达性需按构建机实测记录。
6. 禁止任意 `0.0.0.0/0:443` 长期出站，禁止 TLS inspection；出口网关需具备稳定 EIP、HA、容量和连接跟踪监控。
7. 若使用 `HTTPS_PROXY`，设置 `NO_PROXY=127.0.0.1,localhost,.svc,.cluster.local,<ServiceCIDR>,<PodCIDR>`。
8. 审计整个 namespace 的 NetworkPolicy allow union；检查单份策略不能证明最终封闭。

### 7.3 Service Mesh 与 SSE

- 明确禁止自动注入，或验证 localhost 端口排除、CMAAS TLS passthrough、无 HTTP retry、无响应缓冲、SSE idle timeout 和 drain 时序。
- Mesh/egress proxy 不得终止并重新签发 CMAAS TLS，也不得自动重放生成请求。
- 当前代理的 Kubernetes SIGTERM 排空能力必须实测。`preStop` 和较长 grace period只能作为经压测证明后的机制，不得直接宣称长流一定完成。

> **2026-09-03 虚拟机 Docker SIGTERM 实测（POC-5.1 近似，形态 A）：**
> - 长 SSE 流进行中向容器发 `SIGTERM`：**流被立即中断**，客户端收到 `curl: (18) transfer closed with outstanding read data remaining`，无 `[DONE]`（收到 36 个 chunk、9279 字节后中断）。
> - openai-proxy 收到 SIGTERM 后**不排空在途流**，进程以**退出码 2** 退出；`restart: unless-stopped` 下 Docker 不会自动重启（需显式 `docker start`，`RestartCount=0`）。
> - 恢复后 **2 秒** `/v1/models` 就绪，新非流式请求 200 `CONFIDENTIAL_OK`。
> - 结论：**官方代理无长流排空能力**。K8s 侧 `terminationGracePeriodSeconds: 120` 无法保证在途长流完成——发布窗口与客户端中断契约须经批准，或接受"滚动更新会截断在途流"。此项与文档 7.1"排空能力须经 POC-5 实测，不宣称长流一定完成"一致。

## 8. 阶段 5：LiteLLM 接入

LiteLLM 配置以现场安装版本的 schema 验证为准，示意如下：

```yaml
model_list:
  - model_name: deepseek-v4-confidential
    litellm_params:
      model: openai/<adapter-served-model-name>
      api_base: http://cmaas-deepseek-v4.<namespace>.svc.cluster.local:8080/v1
      api_key: os.environ/CMAAS_ADAPTER_KEY   # 仅形态 B 或 mesh 外的应用鉴权需要
      timeout: 300
      max_retries: 0
```

> **2026-09-04 落实状态（对接公司 LiteLLM，形态 A，已验证通过）**：对接目标为公司已有 LiteLLM（**v1.95.0**，admin UI 维护，`https://aihub.yiling.cn`），模型 `deepseek-v4-confidential` 已建。网络路径选定「Cloudflare Quick Tunnel 临时暴露 VM」，端到端验证通过：`/v1/models` 含该模型 ✅、非流式 `CONFIDENTIAL_OK` ✅、SSE 逐块输出并以 `[DONE]` 结束 ✅。**验证清单 6/6 全部通过**（含零重试对账、无降级、明文泄漏扫描）。
> - **关键踩坑**：① virtual key 需授权该模型（否则 403 `key_model_access_denied`）；② `api_key` 必须非空（否则 LiteLLM 客户端抛 `AuthenticationError`）；③ admin UI 里 `api_base` 不能填集群内 ClusterIP 域名（aihub 服务器解析不到，导致 `Connection error`）；④ `model`（Litellm Model Name）填后端 code `cmaas-deepseek-v4-flash-0731`，不能填成逻辑名 `deepseek-v4-confidential`。
> - `docs/stage5-litellm-integration.md`：admin UI 精确字段映射、隧道操作、验证清单（主文档，已记录 6/6 结果）。
> - `litellm/company-merge-fragment.yaml`：等价 YAML（GitOps 参考）；`litellm/config.yaml`（ClusterIP）/ `config-vm.yaml`（直连 VM）。
> ⚠️ 隧道为**临时联调手段**（随机 URL、公网暴露计费端点、无鉴权），联调完必须关闭；生产 `api_base` 切 K8s ClusterIP（阶段 4 完成后）。⚠️ 实测响应头已确认 `X-Litellm-Attempted-Retries: 0`、`X-Litellm-Attempted-Fallbacks: 0`，但仍建议配置层显式锁死 `max_retries=0`/`cache=false` 作为静态护栏（当前 Raw JSON 缺这些字段）。

1. 不配置到非 TEE 模型的 fallback、model group fallback 或隐式别名切换。
2. 检查 Router、HTTP transport、callback 和 service mesh，证明整条链路没有生成请求自动重试。
3. 关闭或脱敏 LiteLLM 的 prompt/completion、request body、callback、trace 和缓存；不得只依赖 Adapter 脱敏。
4. 业务只看到逻辑模型名；WorkspaceId、后端模型、Adapter key 和 DashScope key不暴露给调用方。
5. LiteLLM `/v1/models` 是业务模型目录；官方代理的 `/v1/models` 只用于内部能力检查。

## 9. 阶段 6：自动化验收

建立唯一入口 `make acceptance`，结果写入 `artifacts/acceptance/<run-id>/`。任何测试失败、证据缺失或命令非零都阻断发布。

| ID | 场景 | 核心断言 |
|---|---|---|
| CT-01 | 非流式 Chat | OpenAI schema、finish reason、usage 和逻辑模型名正确 |
| CT-02 | 模型与 endpoint | 白名单正确；未知模型、Responses、多模态、显式缓存、搜索被拒且上游 0 次 |
| CT-03 | tools | 非流式/SSE tool call、arguments 分片、`role=tool` 第二轮正确 |
| CT-04 | reasoning | 模型支持的 thinking 字段与 `reasoning_content` 正确透传 |
| SSE-01 | 任意分块 | 半个 UTF-8、event 拆分/合并、慢消费者、背压、首字节和 `[DONE]` 正确 |
| SSE-02 | 断连与取消 | Header 前错误可映射；中途断流无 `[DONE]`；客户端取消及时关闭上游 |
| RT-01 | 零重试 | 连接前失败、已发送无响应、首 token 后超时、429、5xx 各层尝试数均为 1 |
| RT-02 | 重复计费 | live 请求与 usage、透明度报告及账单侧证据一一对账 |
| AU-01 | 报告审计 | JSONL 与 materials 完整；篡改、截断、缺失和验证失败均非零 |
| LG-01 | 明文泄漏 | LiteLLM、薄桥、代理、OTel、events、报告对 canary 的扫描符合策略 |
| NW-01 | 网络最小化 | LiteLLM 可访问；selector 单独匹配均不可访问；任意公网 443 不可访问 |
| NW-02 | 证明依赖 | CMAAS、PCCS、Rekor、DNS 和 TLS/SNI 按冻结清单可达，无 MITM |
| KY-01 | 密钥/证明 | 双 key 轮转可用；DashScope key 重建行为已知；证明失败绝不 fallback |
| RL-01 | 限额 | RPM、TPM、协商 RPM、并发上限的 80/100/120% 行为与 429 恢复正确 |
| KU-01 | 滚动与存储 | 跨节点更新无 Multi-Attach；新请求不进 terminating Pod；报告无覆盖 |
| KU-02 | 长 SSE 更新 | 明确证明排空能力；若不能排空，发布窗口和客户端中断契约已批准 |

建议测试目录：

```text
tests/
  contract/ integration/ fault/ load/ k8s/ audit/ security/ live/
artifacts/acceptance/
```

额外网络验收至少包括：

```bash
kubectl auth can-i get secrets \
  --as=system:serviceaccount:<namespace>:<adapter-service-account>

kubectl -n <namespace> get events \
  --field-selector reason=FailedAttachVolume

curl -N --no-buffer http://<litellm-service>/v1/chat/completions ...
```

验收镜像可使用受控诊断变体或 `kubectl debug`；不得为了测试给生产 distroless 镜像加入 shell/curl。

## 10. 阶段 7：容量、SLO 与成本

容量不是简单的 `replicas * workers`。上限近似取以下最小值：

```text
min(LiteLLM 容量,
    薄桥并发上限,
    openai-proxy workers/并发上限,
    CMAAS RPM/TPM,
    密钥协商 RPM 余量,
    CPU/内存/网络,
    CoreDNS/NAT/egress gateway 长连接容量)
```

1. 分别压测稳态、冷启动、扩容、滚动更新和密钥轮转；限制 HPA scale-up 速率并配置 stabilization window。
2. 建立端到端成功率、TTFT、总完成时间、SSE `[DONE]` 完成率、非 TEE 自动完成次数（必须为 0）和审计完整率。
3. Pilot 只设内部 SLO，不承诺外部 SLA。生产 SLA 必须在双副本、故障演练和上游 SLA 对齐后由商务/法务批准。
4. 模型目录必须记录 `model/capability/context/RPM/TPM/price/effective_at/source`，并绑定验证日期。
5. 成本模型按实际模型、输入/输出 token、reasoning 计费规则和北京时区忙闲价格建立；不得把未验证的隐式缓存收益写入预算承诺。
6. 验证预算 50/80/100% 告警、审批、限流和暂停新租户动作；降级只能限流或明确失败，不能改走普通模型。

### 10.1 实测基线（2026-09-04，Docker/VM 直连 192.168.200.128:18080，绕过隧道）

测试对象：`deploy-confidential-adapter-1`，`--workers=2 --max-concurrency=4`，模型 `cmaas-deepseek-v4-flash-0731`。压测规模克制（N≤10、并发≤10，真实计费端点）。

| 指标 | 实测值 | 说明 |
|---|---|---|
| 非流式延迟（顺序 N=8） | avg 0.544s / min 0.414s / max 1.074s | 首请求含建连/密钥协商，后续 ~0.42–0.56s |
| 并发闸门（`max_concurrency=4`） | C≤4 全 200；C=5→4×200+1×429；C=8→4×200+4×429；C=10→4×200+6×429 | 429 体：`Too many concurrent requests` / `rate_limit_error` / `rate_limit_exceeded` |
| SSE TTFT（首 token，N=5） | avg 0.35s | stream=true 首 chunk |
| SSE 完成率（N=5） | 5/5 = 100% | 均收到 `[DONE]` |
| 冷启动就绪（stop→start） | ~0.84s | 容器重启（非镜像拉取），端口关闭后 `docker start` 至 `/v1/models` 200 |
| 审计完整率（N=10） | 10/10 = 100% | `reports-2026-09-04-1.jsonl` 89→99 行，逐请求落记录 |
| 非 TEE 自动完成次数 | 0 | 沿用阶段 5 清单 5 证据（停机无 fallback） |

结论：单 Adapter 容量上限由 `max_concurrency=4` 决定（超并发返回 429、无排队积压放大），稳态延迟亚秒级、SSE 完成率与审计完整率均 100%。此为 Docker 单副本基线，非 SLO 承诺。

### 10.2 未测/待提供项

- **K8s 专属**（阶段 4 阻塞）：HPA scale-up rate / stabilization window、滚动更新、密钥轮转、多副本稳态、PDB。
- **inputs-pending**：`RPM`/`TPM`、`PRICING_SOURCE`、`PILOT_TENANTS`、`LEGAL_SIGN_OFF`、`CONTENT_COMPLIANCE_OWNER` —— 见 `docs/inputs-pending.md` 第 4 节。
- **成本模型**：依赖 `PRICING_SOURCE`（北京时区忙/闲、输入/输出 token、reasoning、缓存命中），未建立预算承诺。

## 11. 阶段 8：发布、轮转与运维

### 11.1 Go/No-Go

由具名 Release Owner 汇总，以下角色在各自领域具有否决权：

- 产品：MVP、用户契约、模型目录和变更通知；
- 商务/法务：邀请资格、特别规则、地域和外部 SLA；
- 安全/合规：fail closed、证明、报告、内容安全和生成标识；
- 技术负责人：能力矩阵、构建来源、错误/SSE 契约；
- SRE/网络：容量、出口、监控、回滚和故障演练；
- FinOps：价格目录、预算和账单对账；
- 业务负责人：内容审核闭环和最终风险接受。

任一否决项或验收证据缺失，不得生产上线。

### 11.2 变更与运维

1. ConfigMap/Secret 环境变量变更必须触发受控 rollout，不假定自动热更新。
2. Adapter key 使用新旧双 key 重叠轮转；DashScope key 轮转需验证代理 worker 重建和协商 RPM。
3. 配置版本、镜像 digest、SDK commit 和模型目录作为一个发布单元回滚。
4. 定期验证镜像签名、SBOM、漏洞、报告审计、NetworkPolicy union、FQDN 漂移和明文 canary。
5. 监控报告 PVC 容量/inode、归档积压、审计失败、证明失败、429、SSE 中断和非预期出站。
6. 真实数据环境发现 `CMAAS_DEBUG=true`、attestation fallback 或非 TEE 路由时立即阻断并进入安全事件流程。

## 12. 交付物

- `docs/adr/001-cmaas-adapter-shape.md`：形态 A/B 的 POC 证据和决策；
- `docs/capability-matrix.md`：按 SDK commit、模型和日期版本化；
- `docs/model-catalog.md`：能力、限额、价格、生效日期和来源；
- `Dockerfile`：固定源码 commit 的多阶段构建；
- `k8s/`：StatefulSet、Service、ServiceAccount、Secret 模板、ConfigMap、PDB、default-deny、ingress/egress/FQDN 策略；
- `litellm/config.yaml`：逻辑模型到独立 Adapter 的唯一映射；
- `tests/`、`Makefile` 和 `artifacts/acceptance/`：统一验收入口与证据；
- 报告归档、`cmaas-audit`、checkpoint state、保留和恢复方案；
- SLO、容量、成本、账单对账、故障演练和具名 go/no-go 记录。

## 13. 官方事实基线

本版文档依据 2026-09-03 可获取的以下官方信息修订：

- 阿里云《百炼 Confidential MaaS 最佳实践》；
- `github.com/dashscope/dashscope-confidential-maas` README、Makefile、`cmd/openai-proxy` 与 `cmd/cmaas-audit` 文档。

实施时必须重新锁定具体 commit 并复核。当前事实包括：代理由源码 `make` 构建；默认监听 `127.0.0.1:8080`、默认 32 workers；支持 Chat Completions、SSE、tools 和 reasoning；不支持 Responses API、多模态、显式缓存与联网搜索；透明度报告由 JSONL 和 `attestation-materials` 共同构成。

2026-09-03 本地 POC 实测补充：tag v0.3.1 直连验证通过，远程证明 Verified（TDX，`debug_enabled=false`）；tools 产生标准 tool call；`thinking_budget` 被接受但 flash 模型不产出 `reasoning_content`；未知顶层字段被静默忽略；多模态与未知模型返回 400。证据目录：`.poc/evidence/`。
