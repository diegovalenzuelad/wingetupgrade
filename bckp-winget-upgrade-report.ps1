# Asegurar uso UTF-8
:OutputEncoding = [System.Text.Encoding]::UTF8

# Resolver winget
$WingetExe = Get-Item "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*\winget.exe" |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1

if (-not $WingetExe) { exit 1 }

# Ejecutar actualización (output estructurado)
& $WingetExe.FullName upgrade --all `
  --accept-source-agreements `
  --accept-package-agreements `
  --output json > $JsonOut

# Leer resultados
$Packages = Get-Content $JsonOut | ConvertFrom-Json

$Rows = foreach ($pkg in $Packages) {
    "<tr>
        <td>$($pkg.Name)</td>
        <td>$($pkg.Id)</td>
        <td>$($pkg.Version)</td>
        <td>$($pkg.AvailableVersion)</td>
        <td>Actualizado</td>
    </tr>"
}

$Date = Get-Date -Format "dd/MM/yyyy HH:mm"

# HTML del reporte
@"
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<title>Reporte semanal Winget</title>
<style>
body { font-family: Segoe UI, Arial; margin:40px; }
h1 { color:#2b579a; }
table { border-collapse: collapse; width: 100%; }
th, td { border: 1px solid #ccc; padding:8px; text-align:left; }
th { background:#f0f0f0; }
.footer { margin-top:30px; font-size:12px; color:#666; }
</style>
</head>
<body>

<h1>Reporte semanal de actualizaciones</h1>

<p><strong>Fecha de ejecución:</strong> $Date</p>
<p><strong>Equipo:</strong> $env:COMPUTERNAME</p>

<table>
<tr>
<th>Aplicación</th>
<th>ID</th>
<th>Versión previa</th>
<th>Versión instalada</th>
<th>Estado</th>
</tr>
$($Rows -join "`n")
</table>

<div class="footer">
Unidad de Informática – Reporte automático Winget
</div>

</body>
</html>
"@ | Out-File $ReportHtml -Encoding UTF8

# Convertir HTML → PDF usando Edge
$Edge = "$env:ProgramFiles(x86)\Microsoft\Edge\Application\msedge.exe"

& $Edge --headless --disable-gpu `
 --print-to-pdf="$ReportPdf" `
 "$ReportHtml"