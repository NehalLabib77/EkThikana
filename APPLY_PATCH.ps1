param(
  [Parameter(Mandatory=$false)]
  [string]$ProjectRoot = "D:\EkThikana_Full_Production"
)

$ErrorActionPreference = "Stop"
$PatchRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$FlutterRoot = Join-Path $ProjectRoot "flutter_app"
$BackendRoot = Join-Path $ProjectRoot "backend"

if (-not (Test-Path $FlutterRoot)) {
  throw "Flutter project not found at $FlutterRoot"
}
if (-not (Test-Path $BackendRoot)) {
  throw "Backend project not found at $BackendRoot"
}

Write-Host "Backing up current lib/backend app..." -ForegroundColor Yellow
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
Copy-Item (Join-Path $FlutterRoot "lib") (Join-Path $FlutterRoot "lib_backup_$Stamp") -Recurse
Copy-Item (Join-Path $BackendRoot "app") (Join-Path $BackendRoot "app_backup_$Stamp") -Recurse

Write-Host "Applying Flutter UI/OCR patch..." -ForegroundColor Cyan
Copy-Item (Join-Path $PatchRoot "flutter_app\lib\*") (Join-Path $FlutterRoot "lib") -Recurse -Force

Write-Host "Applying backend OCR/error-handling patch..." -ForegroundColor Cyan
Copy-Item (Join-Path $PatchRoot "backend\app\*") (Join-Path $BackendRoot "app") -Recurse -Force
Copy-Item (Join-Path $PatchRoot "backend\Dockerfile") (Join-Path $BackendRoot "Dockerfile") -Force
Copy-Item (Join-Path $PatchRoot "backend\requirements.txt") (Join-Path $BackendRoot "requirements.txt") -Force

Write-Host "Adding camera dependency..." -ForegroundColor Cyan
Push-Location $FlutterRoot
flutter pub add image_picker
flutter clean
flutter pub get
flutter analyze
Pop-Location

Write-Host "Patch applied. Next: redeploy backend to Render, then rebuild Flutter with your Render API URL." -ForegroundColor Green
