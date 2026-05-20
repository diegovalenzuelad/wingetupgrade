# ==============================================================================
# Winget Dashboard v2.1 - Automatización + Histórico + HTML + KPIs
# Unidad de Informática - Facultad de Comunicaciones UC
# ==============================================================================

#Requires -Version 5.1

# = ############## AUTO-ELEVACIÓN A ADMINISTRADOR ############## = #
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Solicitando privilegios de Administrador para mapear Winget..." -ForegroundColor Yellow
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process "powershell.exe" -ArgumentList $arguments -Verb RunAs
    Exit
}
# ================================================================== #

$OutputEncoding            = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding  = [System.Text.Encoding]::UTF8

# ============================================================
# 1. CONFIGURACIÓN
# ============================================================
$basePath    = "C:\Scripts"
$reportPath  = "$basePath\Reports"
$exportPath  = "$reportPath\Exports"
$historyPath = "$reportPath\History"
$logPath     = "$reportPath\Logs"

foreach ($p in @($reportPath, $exportPath, $historyPath, $logPath)) {
    if (!(Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}

$dateId       = Get-Date -Format "yyyy-MM-dd_HHmm"
$niceDate     = Get-Date -Format "dd-MM-yyyy HH:mm"
$startTime    = Get-Date

$htmlFile     = "$reportPath\Dashboard_Winget_$dateId.html"
$pdfFile      = "$reportPath\Dashboard_Winget_$dateId.pdf"
$snapshotPre  = "$exportPath\Snapshot_PRE_$dateId.json"
$snapshotPost = "$exportPath\Snapshot_POST_$dateId.json"
$historyFile  = "$historyPath\history.json"
$logFile      = "$logPath\Log_$dateId.txt"

$maxHistory   = 60
$computer     = $env:COMPUTERNAME

# ============================================================
# 2. LOGGING A ARCHIVO
# ============================================================
Start-Transcript -Path $logFile -Encoding UTF8 -Force | Out-Null

Write-Host "=== INICIO WINGET DASHBOARD v2.1 ===" -ForegroundColor Cyan
Write-Host "  Equipo : $computer"   -ForegroundColor Gray
Write-Host "  Inicio : $niceDate"   -ForegroundColor Gray

# Actualizar orígenes antes de parsear para evitar bloqueos interactivos
Write-Host "Sincronizando repositorios de Winget..." -ForegroundColor DarkGray
& winget source update --accept-source-agreements 2>$null | Out-Null

function Get-WingetUpgrades {
    Write-Host "Consultando actualizaciones disponibles vía Winget..." -ForegroundColor Cyan

    # Ejecución limpia y universal (compatible con v1.0 hasta v1.28+)
    # Redirigimos el flujo de error (2>&1) para evitar que avisos bloqueen el script
    $raw = & winget upgrade --accept-source-agreements --accept-package-agreements 2>&1 | Out-String -Width 8192
    
    # Separamos por líneas y removemos espacios en blanco
    $lines = $raw -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
    $apps  = @()

    $dataStarted = $false
    
    foreach ($line in $lines) {
        # 1. Detectar la línea de división de la tabla (los guiones "---")
        if ($line -match "^-{3,}") { 
            $dataStarted = $true 
            continue 
        }
        
        # Ignorar líneas del encabezado o logos de bienvenida
        if (-not $dataStarted) { continue }
        
        # 2. Filtro estricto para limpiar barras de progreso animadas o textos de estado
        if ($line -match "actualizac" -or $line -match "%" -or $line -match "\[" -or $line -match "░" -or $line -match "█" -or $line -match "Verificando") { 
            continue 
        }

        # 3. REGEX Universal por columnas:
        # Busca un nombre, seguido de un ID con estructura de paquete (ej: Microsoft.Edge), y las versiones.
        if ($line -match "^(.+?)\s{2,}([A-Za-z0-9._\-]+(?:\.[A-Za-z0-9._\-]+)+)\s+(\S+)\s+(\S+)") {
            $name = $Matches[1].Trim()
            $id   = $Matches[2].Trim()
            $vOld = $Matches[3].Trim()
            $vNew = $Matches[4].Trim()
            
            # Normalizar el estado si la app está retenida por el sistema
            $estado = "Pendiente"
            if ($line -match "pinned|omitida|bloqueada|blocked") { $estado = "Omitida" }

            $apps += [PSCustomObject]@{
                Aplicacion = $name
                Id         = $id
                VersionOld = $vOld
                VersionNew = $vNew
                Estado     = $estado
            }
        }
    }

    return $apps
}
# ============================================================
# 4. SNAPSHOT PRE-UPGRADE
# ============================================================
Write-Host "`nGenerando snapshot PRE-upgrade..." -ForegroundColor Yellow
try {
    winget export -o $snapshotPre --include-versions --accept-source-agreements 2>$null | Out-Null
    Write-Host "  Guardado: $snapshotPre" -ForegroundColor DarkGray
} catch {
    Write-Warning "No se pudo generar snapshot PRE: $_"
}

# ============================================================
# 5. CONSULTA DE UPGRADES DISPONIBLES (PRE)
# ============================================================
$preUpgrades = Get-WingetUpgrades
Write-Host "  Encontradas: $($preUpgrades.Count) app(s) detectadas en total" -ForegroundColor DarkGray

$pendientes = $preUpgrades | Where-Object { $_.Estado -eq "Pendiente" }
$omitidas   = $preUpgrades | Where-Object { $_.Estado -in @("Omitida", "Bloqueada") }

# ============================================================
# 6. EJECUCIÓN SILENCIOSA DE UPGRADE
# ============================================================
Write-Host "`nEjecutando actualización silenciosa..." -ForegroundColor Green

$wingetArgs = @("upgrade", "--all", "--silent", "--accept-source-agreements", "--accept-package-agreements")
$proc     = Start-Process "winget" -ArgumentList $wingetArgs -NoNewWindow -Wait -PassThru
$exitCode = $proc.ExitCode

Write-Host "  winget exit code: $exitCode" -ForegroundColor DarkGray

# ============================================================
# 7. SNAPSHOT POST-UPGRADE
# ============================================================
Write-Host "`nGenerando snapshot POST-upgrade..." -ForegroundColor Yellow
try {
    winget export -o $snapshotPost --include-versions --accept-source-agreements 2>$null | Out-Null
    Write-Host "  Guardado: $snapshotPost" -ForegroundColor DarkGray
} catch {
    Write-Warning "No se pudo generar snapshot POST: $_"
}

# ============================================================
# 8. VERIFICACIÓN POST
# ============================================================
Write-Host "`nVerificando resultados post-upgrade..." -ForegroundColor Cyan
$postUpgrades = Get-WingetUpgrades
$stillPending = @($postUpgrades | Where-Object { $_.Estado -eq "Pendiente" } | Select-Object -ExpandProperty Id)

# ============================================================
# 9. CLASIFICACIÓN FINAL DE APPS
# ============================================================
$apps = @()
foreach ($app in $pendientes) {
    $estado = if ($app.Id -in $stillPending) { "Fallida" } else { "Actualizada" }
    $apps += [PSCustomObject]@{
        Aplicacion = $app.Aplicacion
        Id         = $app.Id
        VersionOld = $app.VersionOld
        VersionNew = $app.VersionNew
        Estado     = $estado
    }
}
foreach ($app in $omitidas) { $apps += $app }

# ============================================================
# 10. KPIs (Códigos comunes de éxito o sin cambios asimilados)
# ============================================================
$endTime      = Get-Date
$duration     = [math]::Round(($endTime - $startTime).TotalMinutes, 1)

$totalApps    = $apps.Count
$actualizadas = ($apps | Where-Object Estado -eq "Actualizada").Count
$fallidas     = ($apps | Where-Object Estado -eq "Fallida").Count
$omitCount    = ($apps | Where-Object Estado -in @("Omitida", "Bloqueada")).Count

# Control flexible de códigos nativos de Winget (0, sin cambios, o éxito parcial)
$errorCount   = if ($exitCode -eq 0 -or $exitCode -eq -1978335185 -or $exitCode -eq 2313441327) { 0 } else { 1 }

Write-Host "`n--- Resumen ---" -ForegroundColor Cyan
Write-Host "  Total apps  : $totalApps"
Write-Host "  Actualizadas: $actualizadas" -ForegroundColor Green
Write-Host "  Fallidas    : $fallidas"     -ForegroundColor Red
Write-Host "  Omitidas    : $omitCount"    -ForegroundColor Yellow

# ============================================================
# 11. HISTÓRICO JSON CON PODA AUTOMÁTICA
# ============================================================
$execution = [PSCustomObject]@{
    Fecha        = (Get-Date -Format "o")
    Equipo       = $computer
    Total        = $totalApps
    Actualizadas = $actualizadas
    Fallidas     = $fallidas
    Omitidas     = $omitCount
    DuracionMin  = $duration
    ExitCode     = $exitCode
    Apps         = $apps
}

try {
    if (Test-Path $historyFile) {
        $hist = Get-Content $historyFile -Raw -Encoding utf8 | ConvertFrom-Json
        $hist = @($hist) + $execution
    } else {
        $hist = @($execution)
    }
    if ($hist.Count -gt $maxHistory) {
        $hist = $hist | Select-Object -Last $maxHistory
    }
    $hist | ConvertTo-Json -Depth 8 | Out-File $historyFile -Encoding utf8 -Force
} catch {
    Write-Warning "No se pudo actualizar el histórico: $_"
}

# ============================================================
# 12. GENERACIÓN DE FILAS HTML
# ============================================================
$rows = ""
foreach ($a in $apps) {
    $badgeClass = switch ($a.Estado) {
        "Actualizada" { "success"   }
        "Fallida"     { "danger"    }
        "Omitida"     { "warning"   }
        "Bloqueada"   { "secondary" }
        Default       { "info"      }
    }
    $rows += "        <tr>
            <td>$($a.Aplicacion)</td>
            <td><code>$($a.Id)</code></td>
            <td>$($a.VersionOld)</td>
            <td>$($a.VersionNew)</td>
            <td><span class='badge badge-$badgeClass'>$($a.Estado)</span></td>
        </tr>`n"
}
if ($rows -eq "") {
    $rows = "        <tr><td colspan='5' class='empty-row'>Sin actualizaciones disponibles en este ciclo</td></tr>"
}

# ============================================================
# 13. VARIABLES AUXILIARES PARA EL HTML
# ============================================================
$statusColor = if ($fallidas -gt 0 -or $errorCount -eq 1) { "#e63946" } else { "#1db954" }
$statusLabel = if ($fallidas -gt 0 -or $errorCount -eq 1) { "CON ADVERTENCIAS" } else { "EXITOSO" }
$durationStr = "$($duration) min"
$pctOk = if ($totalApps -gt 0) { [math]::Round($actualizadas / $totalApps * 100) } else { 0 }

# ============================================================
# 14. DASHBOARD HTML
# ============================================================
$html = @"
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <title>Dashboard Winget · $computer</title>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&family=JetBrains+Mono&display=swap" rel="stylesheet">
  <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
  <style>
    :root { --navy: #03122E; --gold: #C8A84B; --green: #1db954; --red: #e63946; --amber: #f4a261; --slate: #64748b; --bg: #eef1f6; --surface: #ffffff; --border: #e2e8f0; --text: #1e293b; --muted: #64748b; }
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: 'Inter', sans-serif; background: var(--bg); color: var(--text); font-size: 14px; line-height: 1.6; }
    .header { background: var(--navy); color: white; padding: 36px 48px 32px; position: relative; }
    .header-inner { max-width: 1100px; margin: 0 auto; }
    .header-eyebrow { font-size: 11px; font-weight: 500; letter-spacing: 2px; text-transform: uppercase; opacity: .55; margin-bottom: 8px; }
    .header-title { font-size: 26px; font-weight: 700; letter-spacing: -.5px; margin-bottom: 6px; }
    .header-sub { font-size: 13px; opacity: .6; margin-bottom: 20px; }
    .meta-row { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 18px; }
    .meta-chip { display: inline-flex; align-items: center; gap: 5px; background: rgba(255,255,255,.1); border: 1px solid rgba(255,255,255,.15); border-radius: 6px; padding: 4px 12px; font-size: 12px; font-family: 'JetBrains Mono', monospace; }
    .status-pill { display: inline-flex; align-items: center; gap: 8px; padding: 6px 16px; border-radius: 20px; font-size: 12px; font-weight: 600; background: $statusColor; }
    .main { max-width: 1100px; margin: 0 auto; padding: 32px 24px 48px; }
    .kpi-grid { display: grid; grid-template-columns: repeat(5, 1fr); gap: 14px; margin-bottom: 28px; }
    .kpi-card { background: var(--surface); border-radius: 12px; padding: 20px 18px 16px; border-top: 3px solid var(--border); box-shadow: 0 1px 4px rgba(0,0,0,.06); }
    .kpi-card.c-navy { border-color: var(--navy); } .kpi-card.c-green { border-color: var(--green); } .kpi-card.c-red { border-color: var(--red); } .kpi-card.c-amber { border-color: var(--amber); } .kpi-card.c-gold { border-color: var(--gold); }
    .kpi-value { font-size: 36px; font-weight: 700; line-height: 1; margin-bottom: 4px; }
    .kpi-card.c-navy .kpi-value { color: var(--navy); } .kpi-card.c-green .kpi-value { color: var(--green); } .kpi-card.c-red .kpi-value { color: var(--red); } .kpi-card.c-amber .kpi-value { color: var(--amber); } .kpi-card.c-gold .kpi-value { color: var(--gold); }
    .kpi-label { font-size: 11px; font-weight: 500; text-transform: uppercase; color: var(--muted); }
    .body-grid { display: grid; grid-template-columns: 240px 1fr; gap: 20px; }
    .card { background: var(--surface); border-radius: 12px; box-shadow: 0 1px 4px rgba(0,0,0,.06); overflow: hidden; }
    .card-header { background: var(--navy); color: white; padding: 13px 18px; font-size: 12px; font-weight: 600; text-transform: uppercase; }
    .card-body { padding: 20px; }
    .chart-wrap { position: relative; }
    .chart-center { position: absolute; top: 50%; left: 50%; transform: translate(-50%, -55%); text-align: center; }
    .chart-pct { font-size: 28px; font-weight: 700; color: var(--navy); }
    .table-wrap { overflow-x: auto; }
    table { width: 100%; border-collapse: collapse; }
    thead th { background: #f8fafc; color: var(--muted); font-size: 11px; font-weight: 600; text-transform: uppercase; padding: 10px 14px; border-bottom: 2px solid var(--border); }
    tbody td { padding: 10px 14px; border-bottom: 1px solid #f1f5f9; vertical-align: middle; }
    code { font-family: 'JetBrains Mono', monospace; font-size: 11px; color: var(--muted); background: #f1f5f9; padding: 2px 6px; border-radius: 4px; }
    .badge { display: inline-block; padding: 3px 10px; border-radius: 6px; font-size: 11px; font-weight: 600; }
    .badge-success { background: #d1fae5; color: #065f46; } .badge-danger { background: #fee2e2; color: #991b1b; } .badge-warning { background: #fef9c3; color: #713f12; } .badge-secondary { background: #e2e8f0; color: #475569; }
    .empty-row { text-align: center; padding: 32px !important; color: var(--muted); font-style: italic; }
    .footer { text-align: center; padding: 36px 20px; color: var(--muted); font-size: 12px; border-top: 1px solid var(--border); margin-top: 40px; }
  </style>
</head>
<body>
<div class="header">
  <div class="header-inner">
    <div class="header-eyebrow">Automatización de Software | Windows Server & Client</div>
    <div class="header-title">Dashboard de Actualizaciones Winget</div>
    <div class="header-sub">Unidad de Informática | Facultad de Comunicaciones | UC</div>
    <div class="meta-row">
      <span class="meta-chip">Equipo: $computer</span>
      <span class="meta-chip">Fecha: $niceDate</span>
      <span class="meta-chip">Duración: $durationStr</span>
    </div>
    <span class="status-pill">Proceso: $statusLabel</span>
  </div>
</div>
<div class="main">
  <div class="kpi-grid">
    <div class="kpi-card c-navy"><div class="kpi-value">$totalApps</div><div class="kpi-label">Total apps</div></div>
    <div class="kpi-card c-green"><div class="kpi-value">$actualizadas</div><div class="kpi-label">Actualizadas</div></div>
    <div class="kpi-card c-red"><div class="kpi-value">$fallidas</div><div class="kpi-label">Fallidas</div></div>
    <div class="kpi-card c-amber"><div class="kpi-value">$omitCount</div><div class="kpi-label">Omitidas</div></div>
    <div class="kpi-card c-gold"><div class="kpi-value">$($duration)m</div><div class="kpi-label">Duración</div></div>
  </div>
  <div class="body-grid">
    <div class="card">
      <div class="card-header">Distribución</div>
      <div class="card-body">
        <div class="chart-wrap">
          <canvas id="donut" height="220"></canvas>
          <div class="chart-center"><div class="chart-pct">$pctOk%</div></div>
        </div>
      </div>
    </div>
    <div class="card">
      <div class="card-header">Detalle por aplicación</div>
      <div class="table-wrap">
        <table>
          <thead><tr><th>Aplicación</th><th>ID</th><th>Versión anterior</th><th>Versión nueva</th><th>Estado</th></tr></thead>
          <tbody>$rows</tbody>
        </table>
      </div>
    </div>
  </div>
</div>
<script>
  const ctx = document.getElementById('donut').getContext('2d');
  new Chart(ctx, {
    type: 'doughnut',
    data: {
      labels: ['Actualizadas', 'Fallidas', 'Omitidas'],
      datasets: [{ data: [$actualizadas, $fallidas, $omitCount], backgroundColor: ['#1db954', '#e63946', '#f4a261'], borderWidth: 2 }]
    },
    options: { cutout: '70%', plugins: { legend: { position: 'bottom' } } }
  });
</script>
</body>
</html>
"@

$html | Out-File $htmlFile -Encoding utf8 -Force
Write-Host "`nDashboard HTML generado: $htmlFile" -ForegroundColor Green

# ============================================================
# 15. PDF VÍA EDGE HEADLESS (Con bypass de Sandbox para Administrador)
# ============================================================
try {
    Start-Sleep -Seconds 2
    # --no-sandbox es el secreto para que corra headless bajo procesos elevados
    $edgeArgs = "--headless --disable-gpu --no-sandbox --print-to-pdf=`"$pdfFile`" `"$htmlFile`""
    $edgeProc = Start-Process "msedge.exe" -ArgumentList $edgeArgs -Wait -PassThru -ErrorAction Stop

    if (Test-Path $pdfFile) {
        Write-Host "PDF generado con éxito: $pdfFile" -ForegroundColor Green
    } else {
        Write-Warning "Edge terminó pero no renderizó el PDF."
    }
} catch {
    Write-Warning "No se pudo generar PDF: $_"
}

# ============================================================
# 16. RESUMEN FINAL Y CIERRE
# ============================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  FIN PROCESO  $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Cyan
Write-Host "  Log         : $logFile"
Write-Host "========================================" -ForegroundColor Cyan

Stop-Transcript | Out-Null
Exit 0