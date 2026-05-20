# 1. Configuración de rutas y forzar UTF8 en la sesión de PowerShell
$OutputEncoding = [System.Text.Encoding]::UTF8
$reportPath = "C:\Scripts\Reports"
if (!(Test-Path $reportPath)) { New-Item -ItemType Directory -Path $reportPath }

$date = Get-Date -Format "yyyy-MM-dd_HHmm"
$htmlFile = "$reportPath\Reporte_Winget_$date.html"

Write-Host "Buscando actualizaciones..." -ForegroundColor Cyan

# 2. Captura y procesamiento (Winget a veces devuelve texto en OEM, lo convertimos)
$upgradeTable = winget upgrade --include-unknown --accept-source-agreements | Out-String

# 3. Ejecutar actualización forzada y silenciosa
# --force asegura que se intenten descargar incluso si hay dudas de compatibilidad
winget upgrade --all --silent 

# 4. Lógica de extracción de datos (Regex)
$lines = $upgradeTable -split "`r`n"
$appRows = ""
$foundHeader = $false

foreach ($line in $lines) {
    if ($line -like "*Nombre*Id*Version*Disponible*") { $foundHeader = $true; continue }
    if ($foundHeader -and $line.Trim() -and $line -notmatch "^-") {
        if ($line -match '^(?<Name>.+?)\s+(?<Id>[^\s]+)\s+(?<Version>[^\s]+)\s+(?<Available>[^\s]+)') {
            $name = $matches['Name'].Trim()
            $id = $matches['Id'].Trim()
            $vOld = $matches['Version'].Trim()
            $vNew = $matches['Available'].Trim()

            $appRows += "<tr><td><span class='badge bg-success'><h4 class='display-6 alert alert-success'>Actualizado</h4></span></td><td><strong>$name</strong></td><td class='text-muted small'>$id</td><td><span class='badge bg-secondary'>$vOld</span></td><td><span class='badge bg-primary'>$vNew</span></td></tr>"
        }
    }
}

if ([string]::IsNullOrEmpty($appRows)) {
    $appRows = "<tr><td colspan='5' class='text-center'><h3 class='display-6 alert alert-success'>Sistema actualizado. No se requirieron cambios.</h3></td></tr>"
}

# 4. Generación del HTML con Meta Charset UTF-8
$htmlContent = @"
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Reporte Winget</title>
    <link href="C:/Scripts/assets/bootstrap.min.css" rel="stylesheet">
    
</head>
<body>
    <div class="container sm">
        <div class="card">
            <div class="card-header bg-dark text-center text-light">
                <h3 class="display-4 ">Reporte de Actualizacion de Software</h3>
                
            </div>
            <div class="table-responsive">
                <table class="table table-hover align-middle mb-0">
                    <thead class="">
                        <tr>
                            <th scope="col">Estado</th><th scope="col">Aplicacion</th><th scope="col">ID</th><th scope="col">Anterior</th><th scope="col">Nueva</th>
                        </tr>
                    </thead>
                    <tbody>$appRows</tbody>
                </table>
            </div><br><br>
            <div class="card-footer">
                <p class="text text-center text-body-secondary">
                    &copy; 2026 Unidad de Informatica<br>
                    Facultad de Comunicaciones<br>
                    Pontificia Universidad Catolica de Chile<br>
                </p>
            </div>
        </div>
    </div>
</body>
</html>
"@

# CRITICAL: Guardar usando Encoding UTF8 para evitar símbolos extraños
$htmlContent | Out-File -FilePath $htmlFile -Encoding utf8
Write-Host "Proceso completado. Reporte en: $htmlFile" -ForegroundColor Green

# El comando Exit asegura que el proceso de PowerShell termine
Exit