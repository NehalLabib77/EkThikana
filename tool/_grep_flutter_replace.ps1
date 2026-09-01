Get-ChildItem 'd:\EkThikana_Full_Production_Starter\flutter_app\test' -Recurse |
  Select-Object FullName
Write-Output '---grep---'
Select-String -Path 'd:\EkThikana_Full_Production_Starter\flutter_app\lib\*.dart', 'd:\EkThikana_Full_Production_Starter\flutter_app\lib\**\*.dart' -Pattern 'replaceMaterialFile|updateMaterial' -ErrorAction SilentlyContinue |
  ForEach-Object { Write-Output $_.Line }