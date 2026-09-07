# 本地 SDK POC（后端专家）
# 用途：阶段 0 的 POC-1 前置——验证官方 SDK 构建、cmaas-client 连通、openai-proxy 本地行为。
# 用法：
#   .\scripts\poc\01-local-sdk-poc.ps1 -DASHSCOPE_API_KEY "sk-xxx" -Endpoint "https://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/api/v1/services" -Model "<code>" -Commit "<full-sha>"
# 前置：已安装 Go >= 1.21、make、git。
# 参数来源：优先命令行参数；未提供时从仓库根目录 .env 自动读取（占位保留，最后统一提供）。
# 用法示例：
#   .\scripts\poc\01-local-sdk-poc.ps1            # 全部从 .env 读取
#   .\scripts\poc\01-local-sdk-poc.ps1 -Commit "<full-sha>"

param(
    [string]$DASHSCOPE_API_KEY = "",
    [string]$Endpoint = "",
    [string]$Model = "",
    [string]$Commit = "",
    [string]$RepoUrl = "https://github.com/dashscope/dashscope-confidential-maas.git",
    [string]$WorkDir = "$PSScriptRoot\..\..\.poc"
)

function Load-EnvFile {
    $envFile = Join-Path $PSScriptRoot "..\..\.env"
    if (-not (Test-Path $envFile)) { return }
    $vars = @{}
    Get-Content $envFile -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $i = $line.IndexOf("=")
            $k = $line.Substring(0, $i).Trim()
            $v = $line.Substring($i + 1).Trim()
            $vars[$k] = $v
        }
    }
    if (-not $script:DASHSCOPE_API_KEY) { $script:DASHSCOPE_API_KEY = $vars["DASHSCOPE_API_KEY"] }
    if (-not $script:Model) { $script:Model = $vars["CMAAS_MODEL"] }
    if (-not $script:Endpoint) { $script:Endpoint = $vars["CMAAS_ENDPOINT"] }
    if (-not $script:Endpoint -and $vars["WORKSPACE_ID"]) {
        $script:Endpoint = "https://$($vars['WORKSPACE_ID']).cn-beijing.maas.aliyuncs.com/api/v1/services"
    }
    if (-not $script:Commit) { $script:Commit = $vars["SDK_COMMIT_SHA"] }
}

$ErrorActionPreference = "Continue"  # PS5.1 已知 bug：Stop 下原生命令 stderr 会触发 NativeCommandError
Load-EnvFile
if (-not $DASHSCOPE_API_KEY) { throw "缺少 DASHSCOPE_API_KEY：请在 .env 填写或作为参数传入" }
if (-not $Endpoint) { throw "缺少 CMAAS_ENDPOINT（或 WORKSPACE_ID）：请在 .env 填写或作为参数传入" }
if (-not $Model) { throw "缺少 CMAAS_MODEL：请在 .env 填写或作为参数传入" }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$log = "$WorkDir\poc-run.log"
"=== 本地 SDK POC 开始 $(Get-Date -Format o) ===" | Tee-Object -FilePath $log

# 1. 固定版本构建（官方模块 go.mod 含 replace 指令，go install @version 不可用；
#    改用：下载模块 zip -> 本地解压作为 main module -> go build ./cmd/...）
# 定位 Go 工具链
$goCmd = Get-Command go -ErrorAction SilentlyContinue
if (-not $goCmd) {
    $localGo = "$env:USERPROFILE\.local\go\bin\go.exe"
    if (Test-Path $localGo) { $goCmd = $localGo } else { throw "未找到 Go 工具链" }
}
$goExe = if ($goCmd -is [System.Management.Automation.CommandInfo]) { $goCmd.Source } else { $goCmd }

$env:GOPROXY = "https://goproxy.cn,direct"
$env:GO111MODULE = "on"
$env:GOPATH = "$env:USERPROFILE\.local\gopath"
$BinDir = Join-Path $WorkDir "bin"
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

$module = "github.com/dashscope/dashscope-confidential-maas"
$versionSpec = if ($Commit) { $Commit } else { "latest" }
"解析模块版本: $module@$versionSpec" | Tee-Object -FilePath $log -Append
$modInfo = & $goExe list -m -json "$module@$versionSpec" 2>$null | Out-String
$modInfo | Tee-Object -FilePath $log -Append
$resolved = $modInfo | ConvertFrom-Json
$version = $null
if ($resolved) { $version = $resolved.Version }
if (-not $version) { throw "无法解析 $module 的版本" }

# 官方模块 go.mod 含 replace ./pkg，但 Go 模块 zip 不含 pkg 子模块（release 不完整）。
# 改为从 GitHub 官方 codeload 下载完整源码 tarball（含 pkg/），本地作为 main module 构建。
$tarUrl = if ($Commit) {
    "https://codeload.github.com/dashscope/dashscope-confidential-maas/tar.gz/$Commit"
} else {
    "https://codeload.github.com/dashscope/dashscope-confidential-maas/tar.gz/refs/tags/$version"
}
$tarFile = "$WorkDir\cmaas-$version.tar.gz"
$srcRoot = "$WorkDir\cmaas-src-full"
if (-not (Test-Path $srcRoot)) {
    if (-not (Test-Path $tarFile)) {
        "下载完整源码: $tarUrl" | Tee-Object -FilePath $log -Append
        Invoke-WebRequest -Uri $tarUrl -OutFile $tarFile -UseBasicParsing -TimeoutSec 300
        $hash = (Get-FileHash -Algorithm SHA256 $tarFile).Hash
        "源码 tarball SHA256: $hash" | Tee-Object -FilePath $log -Append
    }
    New-Item -ItemType Directory -Force -Path $srcRoot | Out-Null
    & tar.exe -xzf $tarFile -C $srcRoot 1> "$WorkDir\tar.log" 2> "$WorkDir\tar.err.log"
    if ($LASTEXITCODE -ne 0) { throw "tar 解压失败" }
}
$srcDir = Get-ChildItem -Directory $srcRoot | Select-Object -First 1 -ExpandProperty FullName
if (-not (Test-Path (Join-Path $srcDir "go.mod"))) { throw "模块源码解压异常: $srcDir" }
"源码目录: $srcDir" | Tee-Object -FilePath $log -Append

Push-Location $srcDir
try {
    foreach ($cmd in "cmaas-client", "openai-proxy", "cmaas-audit") {
        "go build ./cmd/$cmd ..." | Tee-Object -FilePath $log -Append
        $bOut = "$WorkDir\go-build-$cmd.log"
        $bErr = "$WorkDir\go-build-$cmd.err.log"
        & $goExe build -o "$BinDir\$cmd.exe" "./cmd/$cmd" 1> $bOut 2> $bErr
        Get-Content $bOut -Encoding UTF8 | Tee-Object -FilePath $log -Append
        Get-Content $bErr -Encoding UTF8 | Tee-Object -FilePath $log -Append
        if ($LASTEXITCODE -ne 0) { throw "go build $cmd 失败" }
    }
}
finally { Pop-Location }

# 记录实际 commit（从模块缓存 .info 提取 Origin.Hash，作为阶段 1 候选基线）
$infoFile = "$env:GOPATH\pkg\mod\cache\download\github.com\dashscope\dashscope-confidential-maas\@v\$version.info"
if (Test-Path $infoFile) {
    $infoJson = Get-Content $infoFile -Raw | ConvertFrom-Json
    $sha = $infoJson.Origin.Hash
    if ($sha) {
        "锁定 commit SHA（阶段 1 候选基线）: $sha" | Tee-Object -FilePath $log -Append
        "COMMIT_SHA=$sha" | Out-File -FilePath "$WorkDir\commit-sha.txt" -Encoding ascii
    }
}

foreach ($bin in "cmaas-client", "openai-proxy", "cmaas-audit") {
    if (-not (Test-Path "$BinDir\$bin.exe")) { throw "缺少产物: $bin.exe" }
}
"构建产物齐全: $BinDir" | Tee-Object -FilePath $log -Append

# 2. cmaas-client 直连验证（非流式 + 流式各一次）
$env:DASHSCOPE_API_KEY = $DASHSCOPE_API_KEY
$client = Join-Path $BinDir "cmaas-client.exe"
"--- 非流式调用 ---" | Tee-Object -FilePath $log -Append
$o1 = "$WorkDir\client-nonstream.log"
& $client --endpoint $Endpoint --model $Model --prompt "只回复 OK" 1> $o1 2> "$o1.err"
Get-Content $o1 -Encoding UTF8 | Tee-Object -FilePath $log -Append
"--- 流式调用 ---" | Tee-Object -FilePath $log -Append
$o2 = "$WorkDir\client-stream.log"
& $client --endpoint $Endpoint --model $Model --prompt "只回复 OK" --stream 1> $o2 2> "$o2.err"
Get-Content $o2 -Encoding UTF8 | Tee-Object -FilePath $log -Append

# 3. openai-proxy 本地行为验证（POC-2 的本地预演）
$proxy = Join-Path $BinDir "openai-proxy.exe"
$p = Start-Process -FilePath $proxy -ArgumentList @(
    "--endpoint", $Endpoint, "--model", $Model,
    "--listen", "127.0.0.1:8080",
    "--transparency-report-dir", "$WorkDir\reports",
    "--no-prompt-in-transparency-report"
) -PassThru -WindowStyle Hidden
try {
    Start-Sleep -Seconds 5
    "--- openai-proxy 非流式 ---" | Tee-Object -FilePath $log -Append
    $p1 = "$WorkDir\proxy-nonstream.log"
    $body1 = '{"model":"' + $Model + '","messages":[{"role":"user","content":"Reply CONFIDENTIAL_OK only"}],"max_tokens":16}'
    $bf1 = "$WorkDir\req-nonstream.json"
    [System.IO.File]::WriteAllText($bf1, $body1, (New-Object System.Text.UTF8Encoding($false)))
    curl.exe -sS http://127.0.0.1:8080/v1/chat/completions -H "Content-Type: application/json" --data-binary "@$bf1" 1> $p1 2> "$p1.err"
    Get-Content $p1 -Encoding UTF8 | Tee-Object -FilePath $log -Append

    "--- openai-proxy 流式 ---" | Tee-Object -FilePath $log -Append
    $p2 = "$WorkDir\proxy-stream.log"
    $body2 = '{"model":"' + $Model + '","messages":[{"role":"user","content":"Reply CONFIDENTIAL_OK only"}],"max_tokens":16,"stream":true}'
    $bf2 = "$WorkDir\req-stream.json"
    [System.IO.File]::WriteAllText($bf2, $body2, (New-Object System.Text.UTF8Encoding($false)))
    curl.exe -sS -N http://127.0.0.1:8080/v1/chat/completions -H "Content-Type: application/json" --data-binary "@$bf2" 1> $p2 2> "$p2.err"
    Get-Content $p2 -Encoding UTF8 | Tee-Object -FilePath $log -Append

    "--- 未知模型拒绝行为 ---" | Tee-Object -FilePath $log -Append
    $p3 = "$WorkDir\proxy-unknown-model.log"
    $body3 = '{"model":"not-in-whitelist","messages":[{"role":"user","content":"x"}]}'
    $bf3 = "$WorkDir\req-unknown-model.json"
    [System.IO.File]::WriteAllText($bf3, $body3, (New-Object System.Text.UTF8Encoding($false)))
    curl.exe -sS -w "`nHTTP_STATUS:%{http_code}`n" http://127.0.0.1:8080/v1/chat/completions -H "Content-Type: application/json" --data-binary "@$bf3" 1> $p3 2> "$p3.err"
    Get-Content $p3 -Encoding UTF8 | Tee-Object -FilePath $log -Append
}
finally {
    if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
}

"=== POC 完成，日志与报告目录：$WorkDir ===" | Tee-Object -FilePath $log -Append
