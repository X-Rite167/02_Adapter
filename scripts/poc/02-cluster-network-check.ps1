# 集群网络 POC（网络专家）
# 用途：阶段 0 的 POC-3——验证调用方限制手段可行性 + CNI 能力 + 出口能力。
# 用法：.\scripts\poc\02-cluster-network-check.ps1            # 从 .env 读取 NAMESPACE（缺省 litellm）
#       .\scripts\poc\02-cluster-network-check.ps1 -Namespace "litellm"
# 前置：kubectl 已配置并可访问目标集群。

param(
    [string]$Namespace = ""
)

if (-not $Namespace) {
    $envFile = Join-Path $PSScriptRoot "..\..\.env"
    if (Test-Path $envFile) {
        Get-Content $envFile -Encoding UTF8 | ForEach-Object {
            $line = $_.Trim()
            if ($line -and -not $line.StartsWith("#") -and $line.StartsWith("NAMESPACE=")) {
                $Namespace = $line.Substring("NAMESPACE=".Length).Trim()
            }
        }
    }
}
if (-not $Namespace) { $Namespace = "litellm" }

$ErrorActionPreference = "Continue"
function Section($t) { "`n=== $t ===" }

# 1. CNI 检测
Section "CNI 检测"
kubectl get pods -n kube-system -l k8s-app=cilium -o name 2>$null | Out-String
kubectl get pods -n kube-system -l app=calico-node -o name 2>$null | Out-String
kubectl get pods -n kube-system -l app=flannel -o name 2>$null | Out-String
kubectl get nodes -o jsonpath="{.items[0].metadata.annotations}" 2>$null | Out-String

# 2. FQDN policy 能力（标准 NetworkPolicy 不支持，必须依赖 CNI）
Section "FQDN policy 能力判断"
kubectl get crd ciliumnetworkpolicies.cilium.io 2>$null | Out-String
kubectl get crd networkpolicies.crd.projectcalico.org 2>$null | Out-String
kubectl get crd globalnetworkpolicies.crd.projectcalico.org 2>$null | Out-String

# 3. 目标 namespace 现状
Section "namespace 现状"
kubectl get ns $Namespace 2>&1 | Out-String
kubectl get networkpolicies -n $Namespace 2>&1 | Out-String

# 4. DNS 解析验证（在轻量 pod 内执行，不要用生产镜像塞 shell）
Section "DNS 解析验证"
kubectl run dns-check-$PID --rm -i --restart=Never --image=busybox:1.36 -n $Namespace -- `
    nslookup confidential-adapter.$Namespace.svc.cluster.local 2>&1 | Out-String

# 5. 出口验证：Adapter 模拟 pod 访问 CMAAS 443 的连通性（DNS + TCP）
Section "CMAAS 出口连通性"
Write-Host "请手动执行（需替换真实 WorkspaceId，并确认出口走 NAT/egress gateway）："
Write-Host "  kubectl run egress-check --rm -i --restart=Never --image=busybox:1.36 -n $Namespace -- nc -vz {WorkspaceId}.cn-beijing.maas.aliyuncs.com 443"
Write-Host "预期：出口受限的集群会 timeout；通过 egress gateway 的集群会 Connected。"

# 6. ServiceAccount 越权基线检查
Section "SA 越权基线"
kubectl auth can-i get secrets --as=system:serviceaccount:$Namespace:default -n $Namespace 2>&1 | Out-String

Section "检查完成。结论请回填 docs/adr/001-cmaas-adapter-shape.md 的 POC-3 行。"
