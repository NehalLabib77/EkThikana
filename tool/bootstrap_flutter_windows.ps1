$ErrorActionPreference = "Stop"

Write-Host "=== EkThikana Flutter Android Bootstrap ===" -ForegroundColor Cyan

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "Flutter is not available in PATH. Install Flutter first and run 'flutter doctor'."
}

$Root = Split-Path -Parent $PSScriptRoot
$FlutterApp = Join-Path $Root "flutter_app"
$Temp = Join-Path $Root ".ekthikana_flutter_shell"

if (Test-Path $Temp) {
    Remove-Item $Temp -Recurse -Force
}

Write-Host "1/5 Creating a clean Android shell..." -ForegroundColor Yellow
flutter create $Temp --platforms=android --org com.ekthikana --project-name ekthikana

if ($LASTEXITCODE -ne 0) {
    throw "flutter create failed."
}

$AndroidTarget = Join-Path $FlutterApp "android"
if (Test-Path $AndroidTarget) {
    Remove-Item $AndroidTarget -Recurse -Force
}
Copy-Item (Join-Path $Temp "android") $AndroidTarget -Recurse -Force

Write-Host "2/5 Patching Android settings..." -ForegroundColor Yellow

$GradleFile = Join-Path $AndroidTarget "app\build.gradle.kts"
$Gradle = Get-Content $GradleFile -Raw

$Gradle = $Gradle -replace 'compileSdk\s*=\s*flutter\.compileSdkVersion', 'compileSdk = 36'
$Gradle = $Gradle -replace 'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 24'
$Gradle = $Gradle -replace 'JavaVersion\.VERSION_11', 'JavaVersion.VERSION_17'
$Gradle = $Gradle -replace 'JavaVersion\.VERSION_1_8', 'JavaVersion.VERSION_17'

if ($Gradle -notmatch 'isCoreLibraryDesugaringEnabled') {
    $Gradle = $Gradle -replace `
        '(compileOptions\s*\{\s*)', `
        "`$1`r`n        isCoreLibraryDesugaringEnabled = true`r`n"
}

if ($Gradle -match 'jvmTarget\s*=\s*JavaVersion\.VERSION_[A-Z0-9_]+\.toString\(\)') {
    $Gradle = $Gradle -replace `
        'jvmTarget\s*=\s*JavaVersion\.VERSION_[A-Z0-9_]+\.toString\(\)', `
        'jvmTarget = JavaVersion.VERSION_17.toString()'
}

if ($Gradle -notmatch 'coreLibraryDesugaring\(') {
    $Gradle += @"

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
"@
}

Set-Content $GradleFile $Gradle -Encoding UTF8

$ManifestFile = Join-Path $AndroidTarget "app\src\main\AndroidManifest.xml"
$Manifest = Get-Content $ManifestFile -Raw

$Manifest = $Manifest -replace 'android:label="ekthikana"', 'android:label="EkThikana"'

if ($Manifest -notmatch 'android\.permission\.POST_NOTIFICATIONS') {
    $Permissions = @"
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
"@
    $Manifest = $Manifest -replace '(<manifest[^>]*>)', "`$1`r`n$Permissions"
}

if ($Manifest -notmatch 'ScheduledNotificationReceiver') {
    $Receivers = @"
        <receiver
            android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver
            android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
"@
    $Manifest = $Manifest -replace '(\s*</application>)', "`r`n$Receivers`$1"
}

Set-Content $ManifestFile $Manifest -Encoding UTF8

$DrawableDir = Join-Path $AndroidTarget "app\src\main\res\drawable"
New-Item -ItemType Directory -Force -Path $DrawableDir | Out-Null

$IconXml = @"
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#263238"
        android:pathData="M12,3L2,12h3v8h6v-6h2v6h6v-8h3L12,3z" />
</vector>
"@
Set-Content (Join-Path $DrawableDir "app_icon.xml") $IconXml -Encoding UTF8

$DebugManifestDir = Join-Path $AndroidTarget "app\src\debug"
New-Item -ItemType Directory -Force -Path $DebugManifestDir | Out-Null
$DebugManifest = @"
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:usesCleartextTraffic="true" />
</manifest>
"@
Set-Content (Join-Path $DebugManifestDir "AndroidManifest.xml") $DebugManifest -Encoding UTF8

Write-Host "3/5 Removing temporary shell..." -ForegroundColor Yellow
Write-Host "3/5 Removing temporary shell..."

Set-Location $PSScriptRoot
Start-Sleep -Seconds 2

Get-Process dart,dartaotruntime -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

Start-Sleep -Seconds 2

$deleted = $false

for ($i = 1; $i -le 5; $i++) {
    try {
        if (Test-Path $Temp) {
            Remove-Item $Temp -Recurse -Force -ErrorAction Stop
        }

        $deleted = $true
        break
    }
    catch {
        Write-Host "Temporary folder is locked. Retry $i/5..."
        Start-Sleep -Seconds 2
    }
}

if (-not $deleted) {
    Write-Warning "Could not remove temporary shell now. Continuing bootstrap; it can be deleted later."
}

Write-Host "4/5 Getting Flutter packages..." -ForegroundColor Yellow
Push-Location $FlutterApp
flutter pub get
if ($LASTEXITCODE -ne 0) {
    Pop-Location
    throw "flutter pub get failed."
}

Write-Host "5/5 Static analysis..." -ForegroundColor Yellow
flutter analyze
$AnalyzeCode = $LASTEXITCODE
Pop-Location

if ($AnalyzeCode -ne 0) {
    Write-Warning "flutter analyze found issues. Fix those before running the app."
} else {
    Write-Host "Flutter analysis passed." -ForegroundColor Green
}

Write-Host ""
Write-Host "NEXT:" -ForegroundColor Cyan
Write-Host "1. cd flutter_app"
Write-Host "2. flutterfire configure"
Write-Host "3. flutter pub get"
Write-Host "4. flutter run --dart-define=API_BASE_URL=http://YOUR_PC_IP:8000"
