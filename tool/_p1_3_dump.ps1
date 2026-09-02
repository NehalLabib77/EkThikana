$api = 'd:\EkThikana_Full_Production_Starter\flutter_app\lib\services\api_service.dart'
$aiSvc = 'd:\EkThikana_Full_Production_Starter\backend\app\services\ai_service.py'
$schemas = 'd:\EkThikana_Full_Production_Starter\backend\app\schemas.py'

Write-Host '===== api_service.dart AI / multipart block ====='
$lines = Get-Content $api
$inblock = $false
$depth = 0
for ($i = 0; $i -lt $lines.Length; $i++) {
    $ln = $lines[$i]
    if ($inblock -or $ln -match 'static Future.*(aiNote|askPdf|askImage|uploadMaterial|updateMaterial|replaceMaterialFile|_multipart)') {
        $inblock = $true
        $depth += ([regex]::Matches($ln, '\{').Count) - ([regex]::Matches($ln, '\}').Count)
        Write-Host ("{0,4}: {1}" -f ($i+1), $ln)
        if ($depth -le 0 -and $inblock) {
            $inblock = $false
            $depth = 0
        }
    }
}

Write-Host ''
Write-Host '===== ai_service.py ====='
Get-Content $aiSvc

Write-Host ''
Write-Host '===== schemas.py AI models ====='
$slines = Get-Content $schemas
$inblock = $false
$depth = 0
for ($i = 0; $i -lt $slines.Length; $i++) {
    $ln = $slines[$i]
    if ($inblock -or $ln -match 'class\s+(AiNoteRequest|PdfQuestionRequest|ImageQuestionRequest|.*[Aa]i.*)') {
        $inblock = $true
        $depth += ([regex]::Matches($ln, '\{').Count) - ([regex]::Matches($ln, '\}').Count)
        Write-Host ("{0,4}: {1}" -f ($i+1), $ln)
        if ($depth -le 0 -and $inblock) {
            $inblock = $false
            $depth = 0
        }
    }
}