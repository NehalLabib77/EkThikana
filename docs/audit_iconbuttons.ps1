$files = @(
  'flutter_app\lib\screens\groups\group_chat_screen.dart',
  'flutter_app\lib\widgets\location_picker.dart',
  'flutter_app\lib\screens\study\material_reader_screen.dart',
  'flutter_app\lib\screens\life\commute_bd_screen.dart',
  'flutter_app\lib\screens\study\ai_assistant_screen.dart',
  'flutter_app\lib\screens\study\academic_structure_screen.dart',
  'flutter_app\lib\screens\groups\groups_screen.dart',
  'flutter_app\lib\screens\study\saved_materials_screen.dart',
  'flutter_app\lib\screens\study\note_editor_screen.dart',
  'flutter_app\lib\screens\life\expense_tracker_screen.dart',
  'flutter_app\lib\screens\study\monthly_money_screen.dart',
  'flutter_app\lib\screens\search\universal_search_screen.dart',
  'flutter_app\lib\screens\study\study_stats_screen.dart',
  'flutter_app\lib\screens\life\bazar_buddy_screen.dart'
)
$root = 'd:\EkThikana_Full_Production_Starter'
$gaps = @()
foreach ($f in $files) {
  $p = Join-Path $root $f
  if (-not (Test-Path $p)) { continue }
  $lines = Get-Content $p
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'IconButton\s*\(') {
      $window = ($lines[$i..([Math]::Min($i+11, $lines.Count-1))] -join "`n")
      $hasTooltip = $window -match 'tooltip\s*:'
      $hasSemLabel = $window -match 'semanticLabel'
      $marker = if ($hasTooltip) {'OK '} elseif ($hasSemLabel) {'SEM'} else {'GAP'}
      $relPath = $f.Replace('\','/')
      Write-Host ("{0,-55} {1,4} [{2}] {3}" -f $relPath,($i+1),$marker,$lines[$i].Trim())
      if (-not $hasTooltip -and -not $hasSemLabel) {
        $gaps += [pscustomobject]@{ File = $relPath; Line = $i + 1; Snippet = $lines[$i].Trim() }
      }
    }
  }
}
Write-Host ""
Write-Host "=== Gaps: $($gaps.Count) ==="
foreach ($g in $gaps) {
  Write-Host ("{0}:{1} :: {2}" -f $g.File, $g.Line, $g.Snippet)
}
