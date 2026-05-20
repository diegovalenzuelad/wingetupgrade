# ==============================================================================
# Winget Dashboard v9.0 - Edicion FCOM Procesador de Texto Plano (HTML + PDF)
# Unidad de Informatica - Facultad de Comunicaciones UC
# ==============================================================================

#Requires -Version 5.1

$OutputEncoding            = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding  = [System.Text.Encoding]::UTF8

# ============================================================
# 1. CONFIGURACION DE RUTAS
# ============================================================
$basePath    = "C:\Scripts"
$reportPath  = "$basePath\Reports"
$exportPath  = "$reportPath\Exports"
$historyPath = "$reportPath\History"
$logPath     = "$reportPath\Logs"

$htmlFile     = "$reportPath\Dashboard_Winget_$(Get-Date -Format 'yyyy-MM-dd_HHmm').html"
$pdfFile      = "$reportPath\Dashboard_Winget_$(Get-Date -Format 'yyyy-MM-dd_HHmm').pdf"
$historyFile  = "$historyPath\history.json"
$txtSource    = "$basePath\prueba_winget.txt" # El archivo que generaste

$computer     = $env:COMPUTERNAME
$niceDate     = Get-Date -Format "dd-MM-yyyy HH:mm"
$startTime    = Get-Date

Write-Host "=== PROCESANDO REPORTE INMUNE TEXTO v9.0 ===" -ForegroundColor Cyan

# ============================================================
# 2. FUNCIÓN: EXTRACCIÓN FILTRADA DE TEXTO CRUDO
# ============================================================
function Convert-TxtToUpgrades {
    if (!(Test-Path $txtSource)) {
        Write-Warning "No se encontro el archivo de origen: $txtSource"
        return @()
    }

    # Leer el archivo forzando codificación UTF8 para saltar caracteres residuales OEM
    $lines = Get-Content -Path $txtSource -Encoding utf8
    $apps = @()
    $foundHeader = $false
    
    foreach ($line in $lines) {
        $line = $line.Trim()
        
        # Detectar el encabezado real de la tabla
        if ($line -like "*Nombre*Id*Versi*Disponible*") {
            $foundHeader = $true
            continue
        }
        if ($line -match "^-{5,}") { continue }
        if (-not $foundHeader) { continue }
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        # REGLA QUIRÚRGICA: Separamos la línea usando múltiples espacios continuos como divisor
        $parts = $line -split '\s{2,}'
        
        # Una aplicación con actualización real obligatoriamente debe entregar entre 4 y 5 columnas:
        # [Nombre, ID, Versión Actual, Versión Disponible, Origen]
        if ($parts.Count -ge 4) {
            $nombre      = $parts[0].Trim()
            $id          = $parts[1].Trim()
            $versionCurr = $parts[2].Trim()
            $versionAvail = $parts[3].Trim()

            # Limpiar caracteres de truncado de consola comunes en winget (ÔÇª o ...)
            $id = $id -replace '[ÔÇª…\.\s]', ''

            # FILTRO CRÍTICO: Si la versión actual es idéntica a la disponible, o la disponible está vacía,
            # o si el ID es simplemente una ruta del registro (ARP), el sistema está al día. No es un upgrade.
            if ($versionCurr -eq $versionAvail -or [string]::IsNullOrWhiteSpace($versionAvail) -or $id -match "^ARP") {
                continue
            }

            # Si pasó los filtros, encontramos un software desactualizado real
            $apps += [PSCustomObject]@{
                Aplicacion = $nombre
                Id         = $id
                VersionOld = $versionCurr
                VersionNew = $versionAvail
                Estado     = "Pendiente"
            }
        }
    }
    return $apps
}

# ============================================================
# 3. EXTRAER Y PROCESAR
# ============================================================
$pendientes  = Convert-TxtToUpgrades
$totalApps   = $pendientes.Count
Write-Host "  [FCOM] Aplicaciones desactualizadas extraidas con exito: $totalApps" -ForegroundColor Yellow

# Simulación de estados para el Dashboard
$actualizadas = $totalApps
$fallidas     = 0
$duration     = 0.2
$statusLabel  = "EXITOSO"
$statusColor  = "#1db954"
$pctOk        = 100

# ============================================================
# 4. CONSTRUCCIÓN DE LA TABLA HTML
# ============================================================
$rows = ""
foreach ($a in $pendientes) {
    $rows += "        <tr>
            <td>$($a.Aplicacion)</td>
            <td><code>$($a.Id)</code></td>
            <td>$($a.VersionOld)</td>
            <td>$($a.VersionNew)</td>
            <td><span class='badge badge-success'>Actualizada</span></td>
        </tr>`n"
}

if ($rows -eq "") {
    $rows = "        <tr><td colspan='5' class='empty-row'>Sin actualizaciones disponibles en este ciclo (Sistema al dia)</td></tr>"
}

# ============================================================
# 5. PLANTILLA HTML EXECUTIVE DASHBOARD
# ============================================================
$html = @"
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <title>Dashboard Winget · $computer</title>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght=400;500;600;700&family=JetBrains+Mono&display=swap" rel="stylesheet">
  <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
  <style>
    :root { --navy: #03122E; --gold: #C8A84B; --green: #1db954; --red: #e63946; --bg: #eef1f6; --surface: #ffffff; --border: #e2e8f0; --text: #1e293b; --muted: #64748b; }
    body { font-family: 'Inter', sans-serif; background: var(--bg); color: var(--text); font-size: 14px; margin:0; padding:0; }
    .header { background: var(--navy); color: white; padding: 36px 48px; }
    .header-title { font-size: 26px; font-weight: 700; margin-bottom: 6px; }
    .header-sub { font-size: 13px; opacity: .6; margin-bottom: 20px; }
    .meta-row { display: flex; gap: 8px; margin-bottom: 18px; }
    .meta-chip { background: rgba(255,255,255,.1); border-radius: 6px; padding: 4px 12px; font-family: 'JetBrains Mono', monospace; font-size: 12px; }
    .status-pill { display: inline-flex; align-items: center; gap: 8px; padding: 6px 16px; border-radius: 20px; font-size: 12px; font-weight: 600; background: $statusColor; }
    .main { max-width: 1100px; margin: 0 auto; padding: 32px 24px; }
    .kpi-grid { display: grid; grid-template-columns: repeat(5, 1fr); gap: 14px; margin-bottom: 28px; }
    .kpi-card { background: var(--surface); border-radius: 12px; padding: 20px; border-top: 3px solid var(--border); box-shadow: 0 1px 4px rgba(0,0,0,.06); }
    .kpi-value { font-size: 36px; font-weight: 700; color: var(--navy); }
    .kpi-label { font-size: 11px; text-transform: uppercase; color: var(--muted); }
    .body-grid { display: grid; grid-template-columns: 260px 1fr; gap: 20px; }
    .card { background: var(--surface); border-radius: 12px; box-shadow: 0 1px 4px rgba(0,0,0,.06); overflow: hidden; }
    .card-header { background: var(--navy); color: white; padding: 13px 18px; font-size: 11px; font-weight: 600; text-transform: uppercase; }
    .card-body { padding: 20px; }
    .chart-wrap { position: relative; }
    .chart-center { position: absolute; top: 50%; left: 50%; transform: translate(-50%, -55%); text-align: center; }
    .chart-pct { font-size: 28px; font-weight: 700; color: var(--navy); }
    table { width: 100%; border-collapse: collapse; }
    thead th { background: #f8fafc; color: var(--muted); font-size: 11px; font-weight: 600; text-transform: uppercase; padding: 10px 14px; border-bottom: 2px solid var(--border); text-align: left; }
    tbody td { padding: 10px 14px; border-bottom: 1px solid #f1f5f9; }
    code { font-family: 'JetBrains Mono', monospace; font-size: 11px; background: #f1f5f9; padding: 2px 6px; border-radius: 4px; }
    .badge { display: inline-block; padding: 3px 10px; border-radius: 6px; font-size: 11px; font-weight: 600; }
    .badge-success { background: #d1fae5; color: #065f46; }
    .empty-row { text-align: center; padding: 32px !important; color: var(--muted); font-style: italic; }
    .footer { text-align: center; padding: 36px; color: var(--muted); font-size: 12px; border-top: 1px solid var(--border); margin-top: 40px; }
  </style>
</head>
<body>
<div class="header">
  <div class="header-title">Dashboard de Actualizaciones Winget</div>
  <div class="header-sub">Unidad de Informatica. Facultad de Comunicaciones. UC</div>
  <div class="meta-row">
    <span class="meta-chip">Equipo: $computer</span>
    <span class="meta-chip">Fecha: $niceDate</span>
    <span class="meta-chip">Duracion: $duration min</span>
  </div>
  <span class="status-pill">Proceso: $statusLabel</span>
</div>
<div class="main">
  <div class="kpi-grid">
    <div class="kpi-card"><div class="kpi-value">$totalApps</div><div class="kpi-label">Total apps</div></div>
    <div class="kpi-card"><div class="kpi-value">$actualizadas</div><div class="kpi-label">Actualizadas</div></div>
    <div class="kpi-card"><div class="kpi-value">$fallidas</div><div class="kpi-label">Fallidas</div></div>
    <div class="kpi-card"><div class="kpi-value">0</div><div class="kpi-label">Omitidas</div></div>
    <div class="kpi-card"><div class="kpi-value">$duration m</div><div class="kpi-label">Duracion</div></div>
  </div>
  <div class="body-grid">
    <div class="card">
      <div class="card-header">Distribucion</div>
      <div class="card-body">
        <div class="chart-wrap">
          <canvas id="donut" height="220"></canvas>
          <div class="chart-center"><div class="chart-pct">$pctOk%</div><div>exito</div></div>
        </div>
      </div>
    </div>
    <div class="card">
      <div class="card-header">Detalle por aplicacion</div>
      <table>
        <thead><tr><th>Aplicacion</th><th>ID</th><th>Version anterior</th><th>Version nueva</th><th>Estado</th></tr></thead>
        <tbody>$rows</tbody>
      </table>
    </div>
  </div>
</div>
<div class="footer">
  <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/d/d8/Marca-uc.svg/330px-Marca-uc.svg.png" style="width:140px; margin-bottom:10px;">
  <p><strong>&copy; 2026 Unidad de Informatica</strong><br>Facultad de Comunicaciones | Pontificia Universidad Catolica de Chile</p>
</div>
<script>
  const ctx = document.getElementById('donut').getContext('2d');
  new Chart(ctx, {
    type: 'doughnut',
    data: {
      labels: ['Actualizadas', 'Fallidas'],
      datasets: [{ data: [$actualizadas, $fallidas], backgroundColor: ['#1db954', '#e63946'], borderWidth: 3 }]
    },
    options: { cutout: '70%', plugins: { legend: { position: 'bottom' } } }
  });
</script>
</body>
</html>
"@

$html | Out-File $htmlFile -Encoding utf8 -Force
Write-Host "Dashboard HTML generado con éxito en: $htmlFile" -ForegroundColor Green

# ============================================================
# 6. EXPORTACIÓN AUTOMÁTICA A PDF EJECUTIVO
# ============================================================
try {
    $htmlUri  = "file:///" + $htmlFile.Replace("\", "/")
    $edgeArgs = @("--headless", "--disable-gpu", "--no-sandbox", "--print-to-pdf=$pdfFile", $htmlUri)
    $edgeProc = Start-Process "msedge.exe" -ArgumentList $edgeArgs -Wait -PassThru -ErrorAction Stop
    if (Test-Path $pdfFile) {
        Write-Host "Dashboard PDF renderizado con éxito en: $pdfFile" -ForegroundColor Green
    }
} catch {
    Write-Warning "No se pudo autocompilar el PDF ejecutivo."
}

Exit 0