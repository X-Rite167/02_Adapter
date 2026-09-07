$ErrorActionPreference = 'Continue'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$out = New-Object System.Collections.Generic.List[string]

$url = "http://192.168.200.128:18080/v1/chat/completions"
$model = "cmaas-deepseek-v4-flash-0731"
$dir = "E:\02_Adapter\.tmp_stage7"
New-Item -ItemType Directory -Force -Path $dir | Out-Null

function New-BodyFile($path, $maxTokens, $stream) {
  $b = @{ model=$model; messages=@(@{role="user"; content="Reply with exactly three words: capacity test"}); max_tokens=$maxTokens; stream=$stream } | ConvertTo-Json -Depth 5
  [System.IO.File]::WriteAllText($path, $b, $utf8NoBom)
}

# ---------- 1. 非流式顺序延迟基线 ----------
$out.Add("=== 1. NON-STREAM SEQUENTIAL LATENCY (N=8) ===")
$lat = @()
for ($i=1; $i -le 8; $i++) {
  $bf = "$dir\ns_$i.json"
  New-BodyFile $bf 16 $false
  $w = curl.exe -s -o "$dir\ns_$i.resp.json" -w "%{http_code} %{time_total} %{time_starttransfer}" -X POST $url -H "Content-Type: application/json" --data-binary "@$bf"
  $parts = $w.Trim() -split ' '
  $code = $parts[0]; $total = $parts[1]; $ttfb = $parts[2]
  $lat += [double]$total
  $out.Add("req=$i code=$code total=${total}s ttfb=${ttfb}s")
}
$lat | Measure-Object -Average -Minimum -Maximum | ForEach-Object {
  $out.Add("SUMMARY avg=$([math]::Round($_.Average,3))s min=$([math]::Round($_.Minimum,3))s max=$([math]::Round($_.Maximum,3))s")
}

# ---------- 2. 并发扫掠（max_concurrency=4） ----------
$out.Add("=== 2. CONCURRENCY SWEEP (1,2,4,8) ===")
foreach ($C in @(1,2,4,8)) {
  $jobs = @()
  for ($j=1; $j -le $C; $j++) {
    $bf = "$dir\c_${C}_${j}.json"
    New-BodyFile $bf 16 $false
    $rf = "$dir\c_${C}_${j}.resp.json"
    $wf = "$dir\c_${C}_${j}.w.txt"
    $p = Start-Process -FilePath "curl.exe" -ArgumentList @("-s","-o",$rf,"-w","%{http_code} %{time_total}","-X","POST",$url,"-H","Content-Type: application/json","--data-binary","@$bf") -RedirectStandardOutput $wf -NoNewWindow -PassThru
    $jobs += $p
  }
  $jobs | ForEach-Object { $_.WaitForExit(120000) | Out-Null }
  $codes = @(); $times = @()
  for ($j=1; $j -le $C; $j++) {
    $wf = "$dir\c_${C}_${j}.w.txt"
    if (Test-Path $wf) {
      $line = (Get-Content $wf -Raw).Trim()
      $p2 = $line -split ' '
      $codes += $p2[0]; if ($p2.Count -ge 2) { $times += [double]$p2[1] }
    }
  }
  $ok = ($codes | Where-Object { $_ -eq '200' }).Count
  $notok = ($codes | Where-Object { $_ -ne '200' })
  $out.Add("C=$C total=$($codes.Count) ok=$ok codes=[$($codes -join ',')]")
}

# ---------- 3. SSE TTFT 与完成率 ----------
$out.Add("=== 3. SSE TTFT & COMPLETION (N=5) ===")
$sseOk = 0; $sseTotal = 0; $sseTtfb = @()
for ($i=1; $i -le 5; $i++) {
  $bf = "$dir\sse_$i.json"
  New-BodyFile $bf 24 $true
  $wf = "$dir\sse_$i.w.txt"
  curl.exe -s -N -o "$dir\sse_$i.resp.txt" -w "%{http_code} %{time_starttransfer}" -X POST $url -H "Content-Type: application/json" --data-binary "@$bf" | Out-File $wf -Encoding ascii
  $line = (Get-Content $wf -Raw).Trim()
  $p2 = $line -split ' '
  $code = $p2[0]; if ($p2.Count -ge 2) { $sseTtfb += [double]$p2[1] }
  $sseTotal++
  $done = (Get-Content "$dir\sse_$i.resp.txt" -Raw) -match '\[DONE\]'
  if ($code -eq '200' -and $done) { $sseOk++ }
  $out.Add("sse=$i code=$code ttfb=$($p2[1])s done=$done")
}
$out.Add("SSE completion: $sseOk/$sseTotal ; ttfb avg=$([math]::Round(($sseTtfb | Measure-Object -Average).Average,3))s")

[System.IO.File]::WriteAllLines("E:\02_Adapter\.tmp_stage7\results.log", $out, $utf8NoBom)
"done"
