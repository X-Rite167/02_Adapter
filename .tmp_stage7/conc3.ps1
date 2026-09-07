$ErrorActionPreference = 'Continue'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$out = New-Object System.Collections.Generic.List[string]
$url = "http://192.168.200.128:18080/v1/chat/completions"
$model = "cmaas-deepseek-v4-flash-0731"
$dir = "E:\02_Adapter\.tmp_stage7"

$out.Add("=== CONCURRENCY SWEEP (.bat parallel, clean codes) ===")

foreach ($C in @(4,5,8)) {
  $bats = @()
  for ($j=1; $j -le $C; $j++) {
    $bf = "$dir\b_${C}_${j}.json"
    $b = @{ model=$model; messages=@(@{role="user"; content="Reply one word: ok"}); max_tokens=8; stream=$false } | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($bf, $b, $utf8NoBom)

    $rf = "$dir\b_${C}_${j}.resp.json"
    $cf = "$dir\b_${C}_${j}.code.txt"
    $bat = "$dir\b_${C}_${j}.bat"
    $line = '@curl.exe -s -o "' + $rf + '" -w "%{http_code}" -X POST "' + $url + '" -H "Content-Type: application/json" --data-binary "@' + $bf + '" > "' + $cf + '" 2>&1'
    [System.IO.File]::WriteAllText($bat, $line, (New-Object System.Text.ASCIIEncoding))
    $bats += $bat
  }
  $procs = @()
  foreach ($bat in $bats) {
    $procs += Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "`"$bat`"" -NoNewWindow -PassThru
  }
  $procs | ForEach-Object { $_.WaitForExit(120000) | Out-Null }

  $codes = @()
  for ($j=1; $j -le $C; $j++) {
    $cf = "$dir\b_${C}_${j}.code.txt"
    if (Test-Path $cf) { $codes += (Get-Content $cf -Raw).Trim() } else { $codes += 'NA' }
  }
  $ok = ($codes | Where-Object { $_ -eq '200' }).Count
  $r429 = ($codes | Where-Object { $_ -eq '429' }).Count
  $other = ($codes | Where-Object { $_ -ne '200' -and $_ -ne '429' })
  $out.Add("C=$C codes=[$($codes -join ',')] ok=$ok 429=$r429 other=[$($other -join ',')]")

  if ($r429 -gt 0) {
    for ($j=1; $j -le $C; $j++) {
      $cf = "$dir\b_${C}_${j}.code.txt"
      if ((Test-Path $cf) -and ((Get-Content $cf -Raw).Trim() -eq '429')) {
        $rf = "$dir\b_${C}_${j}.resp.json"
        $body = (Get-Content $rf -Raw).Trim()
        $out.Add("  429_body: $body")
        break
      }
    }
  }
}

[System.IO.File]::WriteAllLines("E:\02_Adapter\.tmp_stage7\concurrency3.log", $out, $utf8NoBom)
"done"
