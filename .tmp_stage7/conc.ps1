$ErrorActionPreference = 'Continue'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$out = New-Object System.Collections.Generic.List[string]

$url = "http://192.168.200.128:18080/v1/chat/completions"
$model = "cmaas-deepseek-v4-flash-0731"
$dir = "E:\02_Adapter\.tmp_stage7"

$out.Add("=== CONCURRENCY SWEEP (clean, via Start-Job) ===")

foreach ($C in @(1,2,3,4,5,6,8,10)) {
  $jobs = @()
  for ($j=1; $j -le $C; $j++) {
    $bf = "$dir\cc_${C}_${j}.json"
    $b = @{ model=$model; messages=@(@{role="user"; content="Reply with one word: ok"}); max_tokens=8; stream=$false } | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($bf, $b, $utf8NoBom)
    $script = {
      param($bf, $dir, $C, $j, $url)
      $code = curl.exe -s -o "$dir\cc_${C}_${j}.resp.json" -w "%{http_code}" -X POST $url -H "Content-Type: application/json" --data-binary "@$bf"
      $code
    }
    $jobs += Start-Job -ScriptBlock $script -ArgumentList $bf,$dir,$C,$j,$url
  }
  $results = $jobs | Wait-Job | Receive-Job
  $jobs | Remove-Job -Force
  $codes = @()
  foreach ($r in $results) { $codes += $r.Trim() }
  $ok = ($codes | Where-Object { $_ -eq '200' }).Count
  $rate = ($codes | Where-Object { $_ -eq '429' }).Count
  $other = ($codes | Where-Object { $_ -ne '200' -and $_ -ne '429' })
  $out.Add("C=$C codes=[$($codes -join ',')] ok=$ok 429=$rate other=[$($other -join ',')]")
}

[System.IO.File]::WriteAllLines("E:\02_Adapter\.tmp_stage7\concurrency.log", $out, $utf8NoBom)
"done"
