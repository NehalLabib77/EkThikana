# Detached flutter run. Uses Start-Process with redirected stdout/stderr so the
# parent PowerShell never reads the child's pipes (which is what wedged earlier).
$ErrorActionPreference = 'Stop'
Set-Location 'D:\EkThikana_Full_Production_Starter\flutter_app'

$log = Join-Path $env:TEMP ('gochano_run_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')

# Build arg list as a single string for -ArgumentList to keep quoting sane.
$argString = 'run -d 0935625332014966 --dart-define=API_BASE_URL=https://ekthikana-api-x473.onrender.com'

# Use cmd /c so the redirect happens before flutter is exec'd; the parent pwsh
# exits immediately and the grandchild owns its own console.
cmd /c "start /b \"\" flutter $argString > \"$log\" 2>&1"

Write-Output ('LOG=' + $log)
exit 0