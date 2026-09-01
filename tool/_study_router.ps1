Get-Content 'd:\EkThikana_Full_Production_Starter\backend\app\routers\study.py' |
  Select-String -Pattern '^(def |@router\.|async def )' |
  ForEach-Object { Write-Output $_.Line }
Write-Output '---'
(Get-Content 'd:\EkThikana_Full_Production_Starter\backend\app\routers\study.py' -Raw).Split([char]10).Count