Get-ChildItem 'd:\EkThikana_Full_Production_Starter\flutter_app\lib\screens\study' |
  Where-Object { $_.Name -like 'material*' } |
  ForEach-Object {
    $p = $_.FullName
    $n = (Get-Content $p -Raw).Split([char]10).Count
    Write-Output ("{0}  {1}" -f $n, $p)
  }