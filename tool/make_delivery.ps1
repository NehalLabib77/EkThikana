# Builds the extra audit zips (database, assets, android) into .\delivery\
# Excludes generated build artefacts so the archives stay small.
$ErrorActionPreference = 'Stop'
$root = 'd:\EkThikana_Full_Production_Starter'
$out  = Join-Path $root 'delivery'
New-Item -ItemType Directory -Force -Path $out | Out-Null

# --- database.zip : alembic env + versions, migrations/*.sql, SQLAlchemy models ---
$dbStage = Join-Path $out '_db_stage'
if (Test-Path $dbStage) { Remove-Item $dbStage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $dbStage | Out-Null
New-Item -ItemType Directory -Force -Path "$dbStage\alembic" | Out-Null
New-Item -ItemType Directory -Force -Path "$dbStage\migrations" | Out-Null
New-Item -ItemType Directory -Force -Path "$dbStage\app\database" | Out-Null

Copy-Item -Recurse -Force "$root\backend\alembic\*"          "$dbStage\alembic\"  -Exclude '__pycache__','*.pyc'
Copy-Item -Recurse -Force "$root\backend\migrations"         "$dbStage\migrations"
Copy-Item -Recurse -Force "$root\backend\app\database"       "$dbStage\app\database" -Exclude '__pycache__','*.pyc'

if (Test-Path "$out\database.zip") { Remove-Item "$out\database.zip" -Force }
Compress-Archive -Path "$dbStage\*" -DestinationPath "$out\database.zip" -Force
Remove-Item $dbStage -Recurse -Force

# --- assets.zip : only source assets (no build artefacts) ---
if (Test-Path "$out\assets.zip") { Remove-Item "$out\assets.zip" -Force }
Compress-Archive -Path "$root\flutter_app\assets\*" -DestinationPath "$out\assets.zip" -Force

# --- android.zip : exclude .gradle, .kotlin, build, .idea, local.properties, *.iml ---
$androidStage = Join-Path $out '_android_stage'
if (Test-Path $androidStage) { Remove-Item $androidStage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $androidStage | Out-Null

# Copy top-level files (excluding local.properties which holds secrets)
$androidRoot = "$root\flutter_app\android"
Get-ChildItem -Path $androidRoot -File -Force | Where-Object {
    $_.Name -notin @('local.properties','ekthikana_android.iml')
} | ForEach-Object { Copy-Item $_.FullName -Destination $androidStage }

# Copy sub-dirs but skip build/.gradle/.kotlin caches
foreach ($sub in @('app','gradle')) {
    $src = Join-Path $androidRoot $sub
    $dst = Join-Path $androidStage $sub
    if (Test-Path $src) {
        New-Item -ItemType Directory -Force -Path $dst | Out-Null
        Copy-Item -Recurse -Force -Path $src -Destination $dst -Exclude @(
            '.gradle','.kotlin','build','__pycache__','*.pyc','*.iml'
        )
    }
}
# settings.gradle.kts at root
Copy-Item -Path "$androidRoot\settings.gradle.kts" -Destination $androidStage -ErrorAction SilentlyContinue
Copy-Item -Path "$androidRoot\gradle.properties"    -Destination $androidStage -ErrorAction SilentlyContinue
Copy-Item -Path "$androidRoot\build.gradle.kts"     -Destination $androidStage -ErrorAction SilentlyContinue
Copy-Item -Path "$androidRoot\gradlew"              -Destination $androidStage -ErrorAction SilentlyContinue
Copy-Item -Path "$androidRoot\gradlew.bat"          -Destination $androidStage -ErrorAction SilentlyContinue
Copy-Item -Path "$androidRoot\key.properties.example" -Destination $androidStage -ErrorAction SilentlyContinue

if (Test-Path "$out\android.zip") { Remove-Item "$out\android.zip" -Force }
Compress-Archive -Path "$androidStage\*" -DestinationPath "$out\android.zip" -Force
Remove-Item $androidStage -Recurse -Force

Get-ChildItem $out | Select-Object Name, @{N='SizeMB';E={[math]::Round($_.Length/1MB,2)}} | Format-Table -AutoSize
