# ==============================================================================
# Script: Automatización de Actualizaciones Winget con Histórico y Reporte HTML
# Entidad: Unidad de Informática - Facultad de Comunicaciones PUC
# ==============================================================================

# 1. Configuración de Entorno y Rutas
$OutputEncoding = [System.Text.Encoding]::UTF8
$reportPath  = "C:\Scripts\Reports"
$exportPath  = "$reportPath\Exports"
$historyPath = "$reportPath\History"
$assetsPath  = "C:\Scripts\assets"
$imgPath     = "C:\Scripts\img"

# Crear directorios si no existen
foreach ($path in @($reportPath, $exportPath, $historyPath)) {
    if (!(Test-Path $path)) { New-Item -ItemType Directory -Path $path -Force }
}

$date = Get-Date -Format "yyyy-MM-dd_HHmm"
$htmlFile = "$reportPath\Reporte_Winget_$date.html"
$tempFile = "$reportPath\temp_list.txt"
$historyFile = "$historyPath\log_actualizaciones.csv"
$snapShotFile = "$exportPath\Snapshot_$date.json"

Write-Host "Iniciando proceso de mantenimiento..." -ForegroundColor Cyan

# 2. Backup del sistema (Winget Export)
Write-Host "Generando snapshot del sistema..." -ForegroundColor Yellow
& winget export -o $snapShotFile --include-versions --accept-source-agreements

# 3. Captura de actualizaciones disponibles
Write-Host "Buscando actualizaciones..." -ForegroundColor Cyan
& winget upgrade --accept-source-agreements | Out-File $tempFile -Encoding utf8

# 4. Ejecución de la actualización silenciosa
Write-Host "Instalando actualizaciones..." -ForegroundColor Green
& winget upgrade --all --silent --force --accept-package-agreements --accept-source-agreements --include-unknown

# 5. Procesamiento de datos para Reporte e Histórico
$appRows = ""
$foundHeader = $false
$rawContent = Get-Content $tempFile

foreach ($line in $rawContent) {
    $line = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($line) -or $line -match "^-") { continue }
    
    if ($line -match "Nombre|Name" -and $line -match "Id") {
        $foundHeader = $true
        continue
    }

    if ($foundHeader) {
        # Regex para capturar: Nombre, ID, Versión Antigua y Nueva
        if ($line -match '^(?<Name>.+?)\s{2,}(?<Id>[^\s]+)\s{2,}(?<Version>[^\s]+)\s{2,}(?<Available>[^\s]+)') {
            $name = $matches['Name'].Trim()
            $id   = $matches['Id'].Trim()
            $vOld = $matches['Version'].Trim()
            $vNew = $matches['Available'].Trim()

            # Fila para el HTML
            $appRows += @"
                <tr>
                    <td><span class='badge bg-success'>Actualizado</span></td>
                    <td><strong>$name</strong></td>
                    <td class='text-muted small'>$id</td>
                    <td><span class='badge bg-secondary'>$vOld</span></td>
                    <td><span class='badge bg-primary'>$vNew</span></td>
                </tr>
"@
            # Registro en el Histórico CSV
            $logEntry = [PSCustomObject]@{
                Fecha      = (Get-Date -Format "yyyy-MM-dd HH:mm")
                Aplicacion = $name
                ID         = $id
                VersionAnt = $vOld
                VersionNva = $vNew
            }
            $logEntry | Export-Csv -Path $historyFile -Append -NoTypeInformation -Encoding UTF8
        }
    }
}

# Caso de sistema al día
if ([string]::IsNullOrEmpty($appRows)) {
    $appRows = "<tr><td colspan='5' class='text-center text-dark display-6'>No se detectaron actualizaciones pendientes.</td></tr>"
}

# 6. Construcción del Reporte HTML
$htmlContent = @"
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Reporte Winget - UC</title>
    <link href="$assetsPath\bootstrap.min.css" rel="stylesheet">
    <style>
        body { background-color: #f8f9fa; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; }
        .puc-header { background-color: #03122E; color: #fff; border-bottom: 4px solid #004677; }
        .card { border: none; border-radius: 10px; }
        .table-hover tbody tr:hover { background-color: #f1f5f9; }
        .badge { font-weight: 500; }
        .footer-text { font-size: 0.85rem; color: #6c757d; }
    </style>
</head>
<body>
    <div class="container py-5">
        <div class="card shadow">
            <div class="card-header puc-header p-4 text-center">
                <h2 class="display-5 mb-0">Reporte de Actualizacion de Software</h2>
                <small class="text-uppercase tracking-widest">Gestion Automatizada - Windows 11 Pro</small>
            </div>
            <div class="card-body p-0">
                <div class="table-responsive">
                    <table class="table table-hover align-middle mb-0">
                        <thead class="table-dark">
                            <tr>
                                <th>Estado</th>
                                <th>Software</th>
                                <th>ID Programa</th>
                                <th>Anterior</th>
                                <th>Nueva</th>
                            </tr>
                        </thead>
                        <tbody>
                            $appRows
                        </tbody>
                    </table>
                </div>
            </div>
            <div class="card-footer">                          
                <p class="text text-center">
                  <strong>&copy; 2026 Unidad de Informatica</strong><br>
                            Facultad de Comunicaciones<br>
                            Pontificia Universidad Catolica de Chile<br>
                </p>
                    
                    
                
                

            </div>
        </div>
        <img src="C:/Scripts/img/logouc.png" class="card-img-bottom mx-auto d-block" style="width: 200px;" alt="Logo PUC">
    </div>
</body>
</html>
"@

# 7. Guardado y Cierre
$htmlContent | Out-File -FilePath $htmlFile -Encoding utf8
Remove-Item $tempFile -ErrorAction SilentlyContinue

Write-Host "Proceso finalizado. Reporte: $htmlFile" -ForegroundColor Green
Exit