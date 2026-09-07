# 本地 openai-proxy 补充验证（后端专家产出，测试专家执行取证）
# 覆盖：tools 调用、reasoning 字段、未知顶层字段、多模态拒绝
# 用法：.\scripts\poc\03-local-proxy-extra.ps1
# 前置：01-local-sdk-poc.ps1 已执行（.poc\bin 已有产物）

$ErrorActionPreference = "Continue"  # PS5.1 原生命令 stderr 包装 bug 规避

# 从 .env 读取
$envFile = Join-Path $PSScriptRoot "..\..\.env"
$vars = @{}
Get-Content $envFile -Encoding UTF8 | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
        $i = $line.IndexOf("=")
        $vars[$line.Substring(0, $i).Trim()] = $line.Substring($i + 1).Trim()
    }
}
$apiKey = $vars["DASHSCOPE_API_KEY"]
$Model = $vars["CMAAS_MODEL"]
$Endpoint = $vars["CMAAS_ENDPOINT"]
if (-not $Endpoint -and $vars["WORKSPACE_ID"]) {
    $Endpoint = "https://$($vars['WORKSPACE_ID']).cn-beijing.maas.aliyuncs.com/api/v1/services"
}
if (-not $apiKey -or -not $Model -or -not $Endpoint) { throw ".env 参数不完整" }

$WorkDir = "$PSScriptRoot\..\..\.poc"
$evDir = "$WorkDir\evidence\$(Get-Date -Format yyyyMMdd-HHmmss)"
New-Item -ItemType Directory -Force -Path $evDir | Out-Null
$log = "$evDir\run.log"
"=== 补充验证开始 $(Get-Date -Format o) ===" | Tee-Object -FilePath $log

$proxy = "$WorkDir\bin\openai-proxy.exe"
$reports = "$WorkDir\reports-extra"
New-Item -ItemType Directory -Force -Path $reports | Out-Null
$env:DASHSCOPE_API_KEY = $apiKey
$p = Start-Process -FilePath $proxy -ArgumentList @(
    "--endpoint", $Endpoint, "--model", $Model,
    "--listen", "127.0.0.1:8090",
    "--workers", "2",
    "--transparency-report-dir", $reports,
    "--no-prompt-in-transparency-report"
) -PassThru -WindowStyle Hidden

function Invoke-Case([string]$name, [string]$body) {
    $out = "$evDir\$name.log"
    $req = "$evDir\$name.req.json"
    [System.IO.File]::WriteAllText($req, $body, (New-Object System.Text.UTF8Encoding($false)))
    "--- $name ---" | Tee-Object -FilePath $log -Append
    curl.exe -sS -w "`nHTTP_STATUS:%{http_code}`n" http://127.0.0.1:8090/v1/chat/completions -H "Content-Type: application/json" --data-binary "@$req" 1> $out 2> "$out.err"
    Get-Content $out -Encoding UTF8 | Tee-Object -FilePath $log -Append
}

try {
    Start-Sleep -Seconds 6

    # 1. tools 调用（模型应产生 tool call）
    Invoke-Case "tools" ('{"model":"' + $Model + '","messages":[{"role":"user","content":"What is the weather in Beijing now?"}],"tools":[{"type":"function","function":{"name":"get_weather","description":"Get current weather","parameters":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}}}],"tool_choice":"auto","max_tokens":64}')

    # 2. reasoning 字段（thinking_budget）
    Invoke-Case "reasoning" ('{"model":"' + $Model + '","messages":[{"role":"user","content":"1+1=?"}],"thinking_budget":16,"max_tokens":64}')

    # 3. 未知顶层字段（user 字段）——记录被忽略还是被拒绝
    Invoke-Case "unknown-field" ('{"model":"' + $Model + '","messages":[{"role":"user","content":"Reply OK only"}],"max_tokens":16,"user":"abc-123"}')

    # 4. 多模态 content（应被拒绝）
    Invoke-Case "multimodal" ('{"model":"' + $Model + '","messages":[{"role":"user","content":[{"type":"text","text":"describe"},{"type":"image_url","image_url":{"url":"https://example.com/x.png"}}]}],"max_tokens":16}')
}
finally {
    if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
}

"=== 证据目录: $evDir ===" | Tee-Object -FilePath $log -Append
