$ErrorActionPreference = 'Continue'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$url = "http://192.168.200.128:18080/v1/chat/completions"
$model = "cmaas-deepseek-v4-flash-0731"
$dir = "E:\02_Adapter\.tmp_stage7"

$bf = "$dir\sanity_body.json"
$b = @{ model=$model; messages=@(@{role="user"; content="Reply one word: ok"}); max_tokens=8; stream=$false } | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($bf, $b, $utf8NoBom)

$rf = "$dir\sanity.resp.json"
$wf = "$dir\sanity.code.txt"

# 修正：-w 无空格，-o 与 @file 各自独立参数
$p = Start-Process -FilePath "curl.exe" -ArgumentList @(
  "-s","-o",$rf,
  "-w","%{http_code}",
  "-X","POST",
  $url,
  "-H","Content-Type: application/json",
  "--data-binary",("@$bf")
) -RedirectStandardOutput $wf -NoNewWindow -PassThru -Wait

$code = (Get-Content $wf -Raw).Trim()
"code=[$code]"
"body_head=[$((Get-Content $rf -Raw).Substring(0,[Math]::Min(120,(Get-Content $rf -Raw).Length)))]"
