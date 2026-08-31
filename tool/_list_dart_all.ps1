Get-ChildItem 'd:\EkThikana_Full_Production_Starter\flutter_app\lib\services' -ErrorAction SilentlyContinue |
  Select-Object FullName
echo ---WIDGETS---
Get-ChildItem 'd:\EkThikana_Full_Production_Starter\flutter_app\lib\widgets' -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -like '*material*' } |
  Select-Object FullName
echo ---STUDY---
Get-ChildItem 'd:\EkThikana_Full_Production_Starter\flutter_app\lib\screens\study' -ErrorAction SilentlyContinue |
  Select-Object FullName