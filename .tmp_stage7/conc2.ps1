$ErrorActionPreference = 'Continue'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$out = New-Object System.Collections.Generic.List[string]
$url = "http://192.168.200.128:18080/v1/chat/completions"
$model = "cmaas-deepseek-v4-flash-0731"
$dir = "E:\02_Adapter\.tmp_stage7"

$out.Add("=== CONCURRENCY SWEEP (Start-Process, quoted single-string args) ===")

foreach ($C in @(4,5,8)) {
  $procs = @()
  for ($j=1; $j -le $C; $j++) {
    $bf = "$dir\p_${C}_${j}.json"
    $b = @{ model=$model; messages=@(@{role="user"; content="Reply one word: ok"}); max_tokens=8; stream=$false } | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($bf, $b, $utf8NoBom)

    $rf = "$dir\p_${C}_${j}.resp.json"
    $cf = "$dir\p_${C}_${j}.code.txt"
    $args = '-s -o "' + $rf + '" -w "%{http_code}" -X POST "' + $url + '" -H "Content-Type: application/json" --data-binary "@' + $bf + '"'
    $procs += Start-Process -FilePath "curl.exe" -ArgumentList $args -RedirectStandardOutput $cf -NoNewWindow -PassThru
  }
  $procs | ForEach-Object { $_.WaitForExit(120000) | Out-Null }

  $codes = @()
  for ($j=1; $j -le $C; $j++) {
    $cf = "$dir\p_${C}_${j}.code.txt"
    if (Test-Path $cf) { $codes += (Get-Content $cf -Raw).Trim() } else { $codes += 'NA' }
  }
  $ok = ($codes | Where-Object { $_ -eq '200' }).Count
  $r429 = ($codes | Where-Object { $_ -eq '429' }).Count
  $other = ($codes | Where-Object { $_ -ne '200' -and $_ -ne '429' })
  $out.Add("C=$C codes=[$($codes -join ',')] ok=$ok 429=$r429 other=[$($other -join ',')]")

  # 额外：抓取任一 429 的响应体片段
  if ($r429 -gt 0) {
    for ($j=1; $j -le $C; $j++) {
      $cf = "$dir\p_${C}_${j}.code.txt"
      if ((Test-Path $cf) -and ((Get-Content $cf -Raw).Trim() -eq '429')) {
        $rf = "$dir\p_${C}_${j}.resp.json"
        $body = (Get-Content $rf -Raw).Trim()
        $out.Add("  429_body_sample: $($body.Substring(0,[Math]::Min(200,$body.Length)))")
        break
      }
    }
  }
}

[System.IO.File]::WriteAllLines("E:\02_Adapter\.tmp_stage7\concurrency2.log", $out, $utf8NoBom)
"done"
