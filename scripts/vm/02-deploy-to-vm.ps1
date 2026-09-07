# 一键部署到虚拟机 Docker（前提：01-prepare-ssh.ps1 已完成且免密生效）
# 用法：.\scripts\vm\02-deploy-to-vm.ps1                 # 从 .env 读取 VM_HOST/VM_USER/VM_PORT/VM_REMOTE_DIR
#       .\scripts\vm\02-deploy-to-vm.ps1 -VmHost <IP> -VmUser <用户名>   # 命令行覆盖
# 流程：测试连接 -> 打包项目（排除 .poc）-> scp -> 远程 docker compose up -> 验证

param(
    [string]$VmHost = "",
    [string]$VmUser = "",
    [int]$VmPort = 0,
    [string]$RemoteDir = "",
    [string]$KeyFile = "$env:USERPROFILE\.ssh\id_ed25519_02adapter"
)

# 从 .env 读取未提供的参数
$envFile = Join-Path $PSScriptRoot "..\..\.env"
if (Test-Path $envFile) {
    $vars = @{}
    Get-Content $envFile -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $i = $line.IndexOf("=")
            $vars[$line.Substring(0, $i).Trim()] = $line.Substring($i + 1).Trim()
        }
    }
    if (-not $VmHost) { $VmHost = $vars["VM_HOST"] }
    if (-not $VmUser) { $VmUser = $vars["VM_USER"] }
    if ($VmPort -eq 0 -and $vars["VM_PORT"]) { $VmPort = [int]$vars["VM_PORT"] }
    if (-not $RemoteDir -and $vars["VM_REMOTE_DIR"]) { $RemoteDir = $vars["VM_REMOTE_DIR"] }
}
if (-not $VmHost -or -not $VmUser) { Write-Host "缺少 VM_HOST/VM_USER：请在 .env 填写或作为参数传入"; exit 1 }
if ($VmPort -eq 0) { $VmPort = 22 }
if (-not $RemoteDir) { $RemoteDir = "~/02_Adapter" }

$ErrorActionPreference = "Continue"
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
$sshOpts = @("-i", $KeyFile, "-p", $VmPort, "-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=10")
$pkg = "$env:TEMP\02adapter-deploy.tar.gz"

Write-Host "[1/4] 测试连接 ($VmUser@$VmHost`:$VmPort)..."
& ssh @sshOpts "$VmUser@$VmHost" "echo CONNECT_OK && docker --version"
if ($LASTEXITCODE -ne 0) {
    Write-Host "连接失败：若提示输入密码，请直接输入；若提示密钥被拒，先执行 01-prepare-ssh.ps1 配置公钥。"
    exit 1
}

Write-Host "[2/4] 打包并拷贝项目（排除 .poc/.git）..."
Push-Location $root
try {
    & tar.exe -czf $pkg --exclude=.poc --exclude=.git .
    if ($LASTEXITCODE -ne 0) { Write-Host "打包失败"; exit 1 }
}
finally { Pop-Location }
& ssh @sshOpts "$VmUser@$VmHost" "mkdir -p $RemoteDir && rm -rf $RemoteDir/*"
if ($LASTEXITCODE -ne 0) { Write-Host "远端目录准备失败"; exit 1 }
# scp 端口参数为大写 -P（ssh 为小写 -p），需独立选项数组
$scpOpts = @("-i", $KeyFile, "-P", $VmPort, "-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=10")
& scp @scpOpts $pkg "$VmUser@$VmHost`:$RemoteDir/02adapter.tar.gz"
if ($LASTEXITCODE -ne 0) { Write-Host "拷贝失败"; exit 1 }

Write-Host "[3/4] 构建并启动（首次构建需下载基础镜像，约几分钟）..."
& ssh @sshOpts "$VmUser@$VmHost" "cd $RemoteDir && tar -xzf 02adapter.tar.gz && cd deploy && docker compose --env-file ../.env up --build -d && docker compose ps"
if ($LASTEXITCODE -ne 0) { Write-Host "启动失败，检查上一步输出（镜像拉取/构建错误请把输出发回）"; exit 1 }

Write-Host "[4/4] 验证 Adapter..."
& ssh @sshOpts "$VmUser@$VmHost" "curl -sS http://localhost:18080/v1/models"
Write-Host ""
Write-Host "Adapter 部署完成。验证命令（虚拟机/内网任意主机执行）："
Write-Host '  curl -sS http://<虚拟机IP>:18080/v1/chat/completions -H "Content-Type: application/json" -d ''{"model":"cmaas-deepseek-v4-flash-0731","messages":[{"role":"user","content":"Reply CONFIDENTIAL_OK only"}],"max_tokens":16}'''
Write-Host "K8s LiteLLM 接入：api_base 改为 http://<虚拟机IP>:18080/v1（需集群网络可达，见 deploy/README.md）"
