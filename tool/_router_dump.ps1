$root = 'd:\EkThikana_Full_Production_Starter\backend\app\routers'
Get-ChildItem $root -Filter '*.py' | ForEach-Object {
  $path = $_.FullName
  $rel = $path.Substring($path.IndexOf('routers\') + 'routers\'.Length)
  Write-Output "=== $rel ==="
  Select-String -Path $path -Pattern '^(def |@router\.)' |
    ForEach-Object { Write-Output $_.Line }
}