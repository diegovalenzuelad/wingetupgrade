# ============================================================
# Winget Weekly Upgrade + PDF Report (Windows 11 Pro Compatible)
# ============================================================

$ErrorActionPreference = "Stop"
$ProgressPreference   = "SilentlyContinue"
$OutputEncoding       = [System.Text.Encoding]::UTF8

$BasePath   = "C:\Scripts"
$ReportPath = "$BasePath\Reports"
$AssetPath  = "$BasePath\assets"
$Timestamp  = Get-Date -Format "yyyy-MM-dd_HH-mm"

$TextLog = "$ReportPath\Winget_Output_$Timestamp.txt"
$HtmlFile = "$ReportPath\Winget_Report_$Timestamp.html"
$PdfFile  = "$ReportPath\Winget_Report_$Timestamp.pdf"

New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null

# ------------------------------------------------------------
# Winget (ruta segura)
# ------------------------------------------------------------
$Winget = "winget.exe"

# ------------------------------------------------------------
# Ejecutar actualización (SALIDA TEXTO)
# ------------------------------------------------------------
winget upgrade --all `
 --accept-source-agreements `
 --accept-package-agreements `
 | Out-File $TextLog -Encoding UTF8

# ------------------------------------------------------------
# Procesar texto (modo robusto)
# ------------------------------------------------------------
$Content = Get-Content $TextLog -Encoding UTF8

$Rows = @()
foreach ($line in $Content) {
    if ($line -match "^\S") {
        $cols = $line -split "\s{2,}"
        if ($cols.Count -ge 3) {
            $Rows += "<tr><td>$($cols[0])</td><td>$($cols[-2])</td><td>$($cols[-1])</td><td><span class='badge bg-success'><h4 class='display-6 alert alert-success'>Actualizado</h4></span></td></tr>"
        }
    }
}

if ($Rows.Count -eq 0) {
    $Rows += "<tr><td colspan='4' class='text-center'><h3 class='display-6 alert alert-success'>Sistema actualizado. No se requirieron cambios.</h3></td></tr>"
}

# ------------------------------------------------------------
# HTML
# ------------------------------------------------------------
$HtmlContent = @"
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<link href="C:/Scripts/assets/bootstrap.min.css" rel="stylesheet">
<title>Reporte semanal Winget</title>


</head>
<body>

<div class="container">
<h1>Reporte semanal de actualizaciones</h1>
<p><strong>Equipo:</strong> $env:COMPUTERNAME<br>
<strong>Fecha:</strong> $(Get-Date -Format 'dd/MM/yyyy HH:mm')</p>

<table class="table table-bordered table-sm">
<thead>
<tr><th>Aplicación</th><th>Versión</th><th>Disponible</th><th>Estado</th></tr>
</thead>
<tbody>
$($Rows -join "`n")
</tbody>
</table>

<div class="footer">
Unidad de Informática – Reporte automático Winget
</div>
</div>

</body>
</html>
"@

[System.IO.File]::WriteAllText(
  $HtmlFile,
  $HtmlContent,
  [System.Text.UTF8Encoding]::new($false)
)

# ------------------------------------------------------------
# PDF (Edge)
# ------------------------------------------------------------
$Edge = "$env:ProgramFiles(x86)\Microsoft\Edge\Application\msedge.exe"

if (Test-Path $Edge) {
    & $Edge --headless --disable-gpu --print-to-pdf="$PdfFile" "$HtmlFile"
}

exit 0