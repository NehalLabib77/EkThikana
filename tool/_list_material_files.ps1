Get-ChildItem 'd:\EkThikana_Full_Production_Starter\flutter_app\lib\screens' -Recurse -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -like '*material*' -or $_.Name -like '*study*' } |
  Select-Object FullName
echo ---
Get-ChildItem 'd:\EkThikana_Full_Production_Starter\flutter_app\lib\services' -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -like '*material*' } |
  Select-Object FullName