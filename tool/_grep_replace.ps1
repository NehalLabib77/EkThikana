$lines = Get-Content 'd:\EkThikana_Full_Production_Starter\flutter_app\lib\services\api_service.dart'
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match 'replaceMaterialFile|updateMaterial|deleteMaterial|class ApiService|Future<.*> (upload|create|replace|update)') {
    Write-Output ("{0,4}: {1}" -f ($i + 1), $lines[$i])
  }
}