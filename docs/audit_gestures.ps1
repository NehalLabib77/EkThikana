$root = 'd:\EkThikana_Full_Production_Starter\flutter_app\lib'
$files = Get-ChildItem -Path $root -Recurse -Filter '*.dart' | ForEach-Object { $_.FullName }
$gaps = @()
foreach ($p in $files) {
  $rel = $p.Replace($root,'').TrimStart('\','/').Replace('\','/')
  $lines = Get-Content $p
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'GestureDetector\s*\(') {
      $window = ($lines[$i..([Math]::Min($i+10, $lines.Count-1))] -join "`n")
      $hasOnTap = $window -match 'onTap\s*:'
      $hasSem = $window -match 'Semantics\(|semanticLabel|behavior: HitTestBehavior'
      $marker = if ($hasSem) {'OK '} else {'CHK'}
      if ($hasOnTap) {
        Write-Host ("{0,-55} {1,4} [{2}] {3}" -f $rel, ($i+1), $marker, $lines[$i].Trim())
      }
    }
  }
}
