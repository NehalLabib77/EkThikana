# Launch flutter run detached, log to file, return immediately.
$ErrorActionPreference = 'Stop'
Set-Location 'D:\EkThikana_Full_Production_Starter\flutter_app'
$log = Join-Path $env:TEMP ('gochano_run_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
Write-Output ('LOG=' + $log)
$argList = @(
  'run','-d','0935625332014966',
  '--dart-define=API_BASE_URL=https://ekthikana-api-x473.onrender.com',
  '--verbose'
)
$proc = Start-Process -FilePath 'flutter' -ArgumentList $argList -RedirectStandardOutput $log -RedirectStandardError ($log + '.error') -PassThru -WindowStyle Hidden
Write-Output ('PID=' + $proc.Id)
exit 0