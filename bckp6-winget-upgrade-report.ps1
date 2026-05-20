# ==============================================================================
# Winget Dashboard v2 - Automatización + Histórico + HTML + KPIs
# Unidad de Informática - Facultad de Comunicaciones UC
# ==============================================================================
# MEJORAS v2:
#   - Corrección de $args y $error (variables reservadas de PowerShell)
#   - Parser JSON nativo (winget ≥ 1.6) con fallback a texto mejorado
#   - Detección de estados: Actualizada / Fallida / Omitida / Bloqueada
#   - Verificación post-upgrade por comparación de snapshots
#   - Logging a archivo vía Start-Transcript
#   - Histórico con poda automática (máximo configurable)
#   - Dashboard HTML con gráfico donut (Chart.js), columna ID, duración
#   - PDF mejorado con comillas en rutas con espacios
# ==============================================================================

# ============================================================
# AUTO-ELEVACIÓN A ADMINISTRADOR
# ============================================================
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Ejecutando como usuario estándar. Solicitando privilegios de Administrador..." -ForegroundColor Yellow
    
    # Prepara los argumentos para relanzar el mismo script
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    
    # Inicia un nuevo proceso de PowerShell como Administrador
    Start-Process "powershell.exe" -ArgumentList $arguments -Verb RunAs
    
    # Cierra la ventana actual de usuario estándar
    Exit
}
# ============================================================

#Requires -Version 5.1

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

# Máximo de ejecuciones a conservar en el histórico
$maxHistory   = 60

$computer     = $env:COMPUTERNAME

# ============================================================
# 2. LOGGING A ARCHIVO
# ============================================================

Start-Transcript -Path $logFile -Encoding UTF8 -Force | Out-Null

Write-Host "=== INICIO WINGET DASHBOARD v2 ===" -ForegroundColor Cyan
Write-Host "  Equipo : $computer"   -ForegroundColor Gray
Write-Host "  Inicio : $niceDate"   -ForegroundColor Gray


# Forzar la actualización y aceptación de fuentes globalmente antes del parser
winget source update --accept-source-agreements | Out-Null
# ============================================================
# ============================================================
# 3. FUNCIÓN: OBTENER ACTUALIZACIONES DISPONIBLES
# ============================================================
function Get-WingetUpgrades {
    Write-Host "Buscando actualizaciones disponibles vía Winget..." -ForegroundColor Cyan

    # --- Intento 1: Formato JSON (Winget >= 1.6) ---
    try {
        $jsonRaw = & winget upgrade --format json --accept-source-agreements --accept-package-agreements -ErrorAction Stop
        if ($jsonRaw -and $jsonRaw -match '\{.*\}') {
            Write-Host "  [Parser] Datos JSON capturados exitosamente." -ForegroundColor Gray
            $jsonData = ConvertFrom-Json ($jsonRaw | Out-String)
            $apps = @()
            if ($jsonData.Sources -and $jsonData.Sources.Packages) {
                foreach ($pkg in $jsonData.Sources.Packages) {
                    $apps += [PSCustomObject]@{
                        Aplicacion = $pkg.Name
                        Id         = $pkg.Id
                        VersionOld = $pkg.InstalledVersion
                        VersionNew = $pkg.AvailableVersion
                        Estado     = "Pendiente"
                    }
                }
            }
            return $apps
        }
    } catch {
        Write-Host "  [Parser] JSON no soportado o fallido. Pasando a Parser de Texto..." -ForegroundColor Yellow
    }

    # --- Intento 2: Parser de texto por Posición Dinámica (Reemplazo Completo) ---
    Write-Host "  [Parser] Extrayendo columnas por alineación vertical..." -ForegroundColor DarkGray

    # Capturamos la salida e indicamos un ancho de consola plano gigantesco para evitar saltos de línea
    $raw = & winget upgrade --accept-source-agreements --accept-package-agreements --progress-style inline 2>&1 | Out-String -Width 8192
    $lines = $raw -split "`r?`n" | ForEach-Object { $_.TrimEnd() } | Where-Object { $_ -ne "" }

    $apps = @()
    $headerLineIndex = -1

    # 1. Encontrar la línea de encabezados (la que está justo ARRIBA de los guiones "---")
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^-{3,}") {
            $headerLineIndex = $i - 1
            break
        }
    }

    # Si no encontramos la estructura de la tabla, salimos temprano
    if ($headerLineIndex -lt 0) {
        Write-Warning "No se detectó la estructura de tabla nativa de Winget."
        return $apps
    }

    # 2. Calcular dinámicamente los índices (caracteres) donde empieza cada columna
    $headerText = $lines[$headerLineIndex]
    
    $idxId      = $headerText.IndexOf("Id")
    $idxVersion = $headerText.IndexOf("Vers") # Tolera "Versión", "Version", "VersionOld"
    
    # Buscamos dónde termina la columna versión y empieza "Disponible" / "Available"
    $subText    = $headerText.Substring($idxVersion)
    $idxDisp    = $idxVersion + $subText.IndexOf(" ")
    while ($headerText[$idxDisp] -eq " ") { $idxDisp++ } 

    # 3. Rebanar verticalmente cada línea de datos
    for ($i = ($headerLineIndex + 2); $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        
        # Omitir resúmenes del sistema, barras remanentes o textos informativos
        if ($line -match "actualizac" -or $line -match "%" -or $line -match "\[-+" -or $line -match "Verificando") { continue }
        if ($line.Length -lt $idxDisp) { continue }

        try {
            # Cortamos el texto exactamente basándonos en la alineación del encabezado
            $name = $line.Substring(0, $idxId).Trim()
            $id   = $line.Substring($idxId, ($idxVersion - $idxId)).Trim()
            
            # Validación de seguridad: el ID no puede contener espacios.
            # Si falló el corte por posición, usamos un regex de emergencia como último recurso.
            if ($id -match "\s") {
                if ($line -match "^(.+?)\s{2,}(\S+)\s{2,}(\S+)\s{2,}(\S+)") {
                    $name = $Matches[1].Trim()
                    $id   = $Matches[2].Trim()
                    $vOld = $Matches[3].Trim()
                    $vNew = $Matches[4].Trim()
                } else { continue }
            } else {
                $vOld = $line.Substring($idxVersion, ($idxDisp - $idxVersion)).Trim()
                $vNew = $line.Substring($idxDisp).Trim()
                
                # Si la versión nueva viene con el nombre del origen al final (ej: "1.2.3 winget"), lo limpiamos
                if ($vNew -match "^(\S+)\s+(.+)$") { $vNew = $Matches[1].Trim() }
            }

            # Clasificar Estado inicial
            $estado = "Pendiente"
            if ($line -match "pinned|omitida|bloqueada|blocked") { $estado = "Omitida" }

            $apps += [PSCustomObject]@{
                Aplicacion = $name
                Id         = $id
                VersionOld = $vOld
                VersionNew = $vNew
                Estado     = $estado
            }
        } catch {
            # Si una línea rompe el substr, la ignoramos de forma segura
            continue
        }
    }

    return $apps
}
# ============================================================
# 4. SNAPSHOT PRE-UPGRADE
# ============================================================

Write-Host "`nGenerando snapshot PRE-upgrade..." -ForegroundColor Yellow
try {
    winget export -o $snapshotPre --include-versions --accept-source-agreements 2>$null
    Write-Host "  Guardado: $snapshotPre" -ForegroundColor DarkGray
} catch {
    Write-Warning "No se pudo generar snapshot PRE: $_"
}

# ============================================================
# 5. CONSULTA DE UPGRADES DISPONIBLES (PRE)
# ============================================================

Write-Host "`nConsultando actualizaciones disponibles..." -ForegroundColor Cyan
$preUpgrades = Get-WingetUpgrades
Write-Host "  Encontradas: $($preUpgrades.Count) app(s) pendientes" -ForegroundColor DarkGray

$pendientes = $preUpgrades | Where-Object { $_.Estado -eq "Pendiente" }
$omitidas   = $preUpgrades | Where-Object { $_.Estado -in @("Omitida", "Bloqueada") }

# ============================================================
# 6. EJECUCIÓN SILENCIOSA DE UPGRADE
#    NOTA: $wingetArgs (no $args, que es variable reservada de PS)
# ============================================================

Write-Host "`nEjecutando actualización silenciosa..." -ForegroundColor Green


$wingetProcPath = Get-ChildItem -Path "C:\Program Files\WindowsApps" -Filter "winget.exe" -Recurse -ErrorAction SilentlyContinue | 
                   Where-Object { $_.FullName -match "x64" } | 
                   Select-Object -ExpandProperty FullName -First 1

if (-not $wingetProcPath) { $wingetProcPath = "winget.exe" }

$proc     = Start-Process $wingetProcPath -ArgumentList $wingetArgs -NoNewWindow -Wait -PassThru
$exitCode = $proc.ExitCode

Write-Host "  winget exit code: $exitCode" -ForegroundColor DarkGray

# ============================================================
# 7. SNAPSHOT POST-UPGRADE
# ============================================================

Write-Host "`nGenerando snapshot POST-upgrade..." -ForegroundColor Yellow
try {
    winget export -o $snapshotPost --include-versions --accept-source-agreements 2>$null
    Write-Host "  Guardado: $snapshotPost" -ForegroundColor DarkGray
} catch {
    Write-Warning "No se pudo generar snapshot POST: $_"
}

# ============================================================
# 8. VERIFICACIÓN POST
#    Apps que siguen pendientes después del upgrade = Fallidas
# ============================================================

Write-Host "`nVerificando resultados post-upgrade..." -ForegroundColor Cyan
$postUpgrades = Get-WingetUpgrades
$stillPending = @($postUpgrades | Where-Object { $_.Estado -eq "Pendiente" } |
                  Select-Object -ExpandProperty Id)

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

foreach ($app in $omitidas) {
    $apps += $app
}

# ============================================================
# 10. KPIs (Ajustado para tolerar códigos nativos de Winget)
# ============================================================
$endTime      = Get-Date
$duration     = [math]::Round(($endTime - $startTime).TotalMinutes, 1)

$totalApps    = $apps.Count
$actualizadas = ($apps | Where-Object Estado -eq "Actualizada").Count
$fallidas     = ($apps | Where-Object Estado -eq "Fallida").Count
$omitCount    = ($apps | Where-Object Estado -in @("Omitida", "Bloqueada")).Count

# Si winget devuelve 0 es éxito. Si devuelve códigos comunes de "no hay cambios" o "éxito parcial", lo tratamos como 0.
# Códigos comunes de Winget: 0x8a15002f o -1978335185 suelen significar "sin cambios" o "completado con advertencias"
$errorCount   = if ($exitCode -eq 0 -or $exitCode -eq -1978335185 -or $exitCode -eq 2313441327) { 0 } else { 1 }

# ============================================================
# 11. HISTÓRICO JSON CON PODA AUTOMÁTICA
# ============================================================

$execution = [PSCustomObject]@{
    Fecha        = (Get-Date -Format "o")   # ISO 8601 para fácil parsing
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

    # Poda: conservar solo las últimas $maxHistory ejecuciones
    if ($hist.Count -gt $maxHistory) {
        $hist = $hist | Select-Object -Last $maxHistory
        Write-Host "  [Histórico] Poda aplicada: se conservan las últimas $maxHistory ejecuciones" -ForegroundColor DarkGray
    }

    $hist | ConvertTo-Json -Depth 8 | Out-File $historyFile -Encoding utf8 -Force
    Write-Host "  Histórico actualizado ($($hist.Count)/$maxHistory ejecuciones)" -ForegroundColor DarkGray

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
# Si hay aplicaciones fallidas, alertamos. Si todo lo detectado se actualizó u omitió, es EXITOSO.
$statusColor = if ($fallidas -gt 0 -or $errorCount -eq 1) { "#e63946" } else { "#1db954" }
$statusLabel = if ($fallidas -gt 0 -or $errorCount -eq 1) { "CON ADVERTENCIAS" } else { "EXITOSO" }
$durationStr = "$($duration) min"

# ============================================================
# 14. DASHBOARD HTML
# ============================================================

$html = @"
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Dashboard Winget · $computer</title>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
  <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
  <style>
    :root {
      --navy:    #03122E;
      --gold:    #C8A84B;
      --green:   #1db954;
      --red:     #e63946;
      --amber:   #f4a261;
      --slate:   #64748b;
      --bg:      #eef1f6;
      --surface: #ffffff;
      --border:  #e2e8f0;
      --text:    #1e293b;
      --muted:   #64748b;
    }

    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

    body {
      font-family: 'Inter', sans-serif;
      background: var(--bg);
      color: var(--text);
      font-size: 14px;
      line-height: 1.6;
    }

    /* ── HEADER ─────────────────────────────────────── */
    .header {
      background: var(--navy);
      color: white;
      padding: 36px 48px 32px;
      position: relative;
      overflow: hidden;
    }
    .header::before {
      content: '';
      position: absolute;
      right: -80px; top: -80px;
      width: 340px; height: 340px;
      border-radius: 50%;
      background: rgba(200,168,75,.1);
      pointer-events: none;
    }
    .header::after {
      content: '';
      position: absolute;
      right: 60px; top: 60px;
      width: 180px; height: 180px;
      border-radius: 50%;
      background: rgba(200,168,75,.06);
      pointer-events: none;
    }
    .header-inner { position: relative; z-index: 1; max-width: 1100px; margin: 0 auto; }
    .header-eyebrow {
      font-size: 11px; font-weight: 500; letter-spacing: 2px;
      text-transform: uppercase; opacity: .55; margin-bottom: 8px;
    }
    .header-title {
      font-size: 26px; font-weight: 700;
      letter-spacing: -.5px; margin-bottom: 6px;
    }
    .header-sub { font-size: 13px; opacity: .6; margin-bottom: 20px; }

    .meta-row { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 18px; }
    .meta-chip {
      display: inline-flex; align-items: center; gap: 5px;
      background: rgba(255,255,255,.1); border: 1px solid rgba(255,255,255,.15);
      border-radius: 6px; padding: 4px 12px;
      font-size: 12px; font-family: 'JetBrains Mono', monospace;
    }

    .status-pill {
      display: inline-flex; align-items: center; gap: 8px;
      padding: 6px 16px; border-radius: 20px;
      font-size: 12px; font-weight: 600; letter-spacing: .5px;
      background: $statusColor;
    }
    .status-pill::before {
      content: ''; width: 7px; height: 7px;
      border-radius: 50%; background: rgba(255,255,255,.7);
      display: inline-block;
    }

    /* ── LAYOUT ──────────────────────────────────────── */
    .main { max-width: 1100px; margin: 0 auto; padding: 32px 24px 48px; }

    /* ── KPI GRID ────────────────────────────────────── */
    .kpi-grid {
      display: grid;
      grid-template-columns: repeat(5, 1fr);
      gap: 14px;
      margin-bottom: 28px;
    }
    @media (max-width: 800px) { .kpi-grid { grid-template-columns: repeat(3, 1fr); } }
    @media (max-width: 520px) { .kpi-grid { grid-template-columns: repeat(2, 1fr); } }

    .kpi-card {
      background: var(--surface);
      border-radius: 12px;
      padding: 20px 18px 16px;
      border-top: 3px solid var(--border);
      box-shadow: 0 1px 4px rgba(0,0,0,.06);
      transition: transform .15s, box-shadow .15s;
    }
    .kpi-card:hover { transform: translateY(-2px); box-shadow: 0 4px 16px rgba(0,0,0,.1); }
    .kpi-card.c-navy   { border-color: var(--navy); }
    .kpi-card.c-green  { border-color: var(--green); }
    .kpi-card.c-red    { border-color: var(--red); }
    .kpi-card.c-amber  { border-color: var(--amber); }
    .kpi-card.c-gold   { border-color: var(--gold); }

    .kpi-value {
      font-size: 36px; font-weight: 700; line-height: 1;
      letter-spacing: -1px; margin-bottom: 4px;
    }
    .kpi-card.c-navy  .kpi-value { color: var(--navy);  }
    .kpi-card.c-green .kpi-value { color: var(--green); }
    .kpi-card.c-red   .kpi-value { color: var(--red);   }
    .kpi-card.c-amber .kpi-value { color: var(--amber); }
    .kpi-card.c-gold  .kpi-value { color: var(--gold);  }

    .kpi-label {
      font-size: 11px; font-weight: 500; text-transform: uppercase;
      letter-spacing: 1px; color: var(--muted);
    }

    /* ── BODY GRID ───────────────────────────────────── */
    .body-grid {
      display: grid;
      grid-template-columns: 240px 1fr;
      gap: 20px;
    }
    @media (max-width: 750px) { .body-grid { grid-template-columns: 1fr; } }

    /* ── CARD ────────────────────────────────────────── */
    .card {
      background: var(--surface);
      border-radius: 12px;
      box-shadow: 0 1px 4px rgba(0,0,0,.06);
      overflow: hidden;
    }
    .card-header {
      background: var(--navy);
      color: white;
      padding: 13px 18px;
      font-size: 12px;
      font-weight: 600;
      letter-spacing: .5px;
      text-transform: uppercase;
    }
    .card-body { padding: 20px; }

    /* ── CHART ───────────────────────────────────────── */
    .chart-wrap { position: relative; }
    .chart-center {
      position: absolute; top: 50%; left: 50%;
      transform: translate(-50%, -55%);
      text-align: center; pointer-events: none;
    }
    .chart-pct { font-size: 28px; font-weight: 700; color: var(--navy); line-height: 1; }
    .chart-lbl { font-size: 10px; text-transform: uppercase; letter-spacing: 1px; color: var(--muted); }

    /* ── TABLE ───────────────────────────────────────── */
    .table-wrap { overflow-x: auto; }
    table { width: 100%; border-collapse: collapse; }
    thead th {
      background: #f8fafc;
      color: var(--muted);
      font-size: 11px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: .5px;
      padding: 10px 14px;
      border-bottom: 2px solid var(--border);
      white-space: nowrap;
    }
    tbody td { padding: 10px 14px; border-bottom: 1px solid #f1f5f9; vertical-align: middle; }
    tbody tr:last-child td { border-bottom: none; }
    tbody tr:hover { background: #fafbfd; }

    code {
      font-family: 'JetBrains Mono', monospace;
      font-size: 11px; color: var(--muted);
      background: #f1f5f9; padding: 2px 6px; border-radius: 4px;
    }

    .badge {
      display: inline-block;
      padding: 3px 10px; border-radius: 6px;
      font-size: 11px; font-weight: 600; letter-spacing: .3px;
    }
    .badge-success   { background: #d1fae5; color: #065f46; }
    .badge-danger    { background: #fee2e2; color: #991b1b; }
    .badge-warning   { background: #fef9c3; color: #713f12; }
    .badge-secondary { background: #e2e8f0; color: #475569; }
    .badge-info      { background: #dbeafe; color: #1e40af; }

    .empty-row { text-align: center; padding: 32px !important; color: var(--muted); font-style: italic; }

    /* ── FOOTER ──────────────────────────────────────── */
    .footer {
      text-align: center; padding: 36px 20px 40px;
      color: var(--muted); font-size: 12px;
      border-top: 1px solid var(--border);
      margin-top: 40px;
    }
    .footer img  { width: 140px; margin-bottom: 12px; display: block; margin: 0 auto 14px; opacity: .9; }
    .footer strong { color: var(--navy); }
    .footer .exitcode {
      display: inline-block; margin-top: 10px;
      font-family: 'JetBrains Mono', monospace; font-size: 11px;
      background: #f1f5f9; padding: 4px 12px; border-radius: 6px; color: var(--slate);
    }
  </style>
</head>
<body>

<!-- ════════════════════ HEADER ════════════════════ -->
<div class="header">
  <div class="header-inner">
    <div class="header-eyebrow">Automatizacion de Software | Windows 11 Pro</div>
    <div class="header-title">Dashboard de Actualizaciones Winget</div>
    <div class="header-sub">
      Unidad de Informatica. Facultad de Comunicaciones.
      Pontificia Universidad Catolica de Chile
    </div>
    <div class="meta-row">
      <span class="meta-chip">Equipo: $computer</span>
      <span class="meta-chip">Fecha: $niceDate</span>
      <span class="meta-chip">Duracion:$durationStr</span>
    </div>
    <span class="status-pill">Proceso: $statusLabel</span>
  </div>
</div>

<!-- ════════════════════ MAIN ════════════════════ -->
<div class="main">

  <!-- KPIs -->
  <div class="kpi-grid">
    <div class="kpi-card c-navy">
      <div class="kpi-value">$totalApps</div>
      <div class="kpi-label">Total apps</div>
    </div>
    <div class="kpi-card c-green">
      <div class="kpi-value">$actualizadas</div>
      <div class="kpi-label">Actualizadas</div>
    </div>
    <div class="kpi-card c-red">
      <div class="kpi-value">$fallidas</div>
      <div class="kpi-label">Fallidas</div>
    </div>
    <div class="kpi-card c-amber">
      <div class="kpi-value">$omitCount</div>
      <div class="kpi-label">Omitidas</div>
    </div>
    <div class="kpi-card c-gold">
      <div class="kpi-value">$($duration)m</div>
      <div class="kpi-label">Duracion</div>
    </div>
  </div>

  <!-- BODY: Chart + Tabla -->
  <div class="body-grid">

    <!-- Donut chart -->
    <div class="card">
      <div class="card-header">Distribucion</div>
      <div class="card-body">
        <div class="chart-wrap">
          <canvas id="donut" height="220"></canvas>
          <div class="chart-center">
            <div class="chart-pct">$pctOk%</div>
            <div class="chart-lbl">exito</div>
          </div>
        </div>
      </div>
    </div>

    <!-- Tabla de apps -->
    <div class="card">
      <div class="card-header">Detalle por aplicacion</div>
      <div class="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Aplicacion</th>
              <th>ID</th>
              <th>Version anterior</th>
              <th>Version nueva</th>
              <th>Estado</th>
            </tr>
          </thead>
          <tbody>
$rows
          </tbody>
        </table>
      </div>
    </div>

  </div><!-- /body-grid -->
</div><!-- /main -->

<!-- ════════════════════ FOOTER ════════════════════ -->
<div class="footer">
  <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/d/d8/Marca-uc.svg/330px-Marca-uc.svg.png" alt="Logo Pontificia Universidad Católica de Chile">
  <p>
    <strong>&copy; 2026 Unidad de Informatica</strong><br>
    Facultad de Comunicaciones | Pontificia Universidad Catolica de Chile
  </p>
  <!-- <div class="exitcode">winget exit code: $exitCode &nbsp;·&nbsp; Log: $logFile</div> -->
</div>

<script>
  const ctx   = document.getElementById('donut').getContext('2d');
  const total = $totalApps;

  new Chart(ctx, {
    type: 'doughnut',
    data: {
      labels:   ['Actualizadas', 'Fallidas', 'Omitidas'],
      datasets: [{
        data:            [$actualizadas, $fallidas, $omitCount],
        backgroundColor: ['#1db954', '#e63946', '#f4a261'],
        borderWidth:     3,
        borderColor:     '#ffffff',
        hoverOffset:     6
      }]
    },
    options: {
      cutout: '70%',
      animation: { animateScale: true, duration: 900 },
      plugins: {
        legend: {
          position: 'bottom',
          labels: {
            font: { size: 11, family: 'Inter' },
            padding: 14,
            usePointStyle: true,
            pointStyleWidth: 10
          }
        },
        tooltip: {
          callbacks: {
            label: ctx => {
              const pct = total > 0 ? Math.round(ctx.parsed / total * 100) : 0;
              return ` `+ ctx.label + `: ` + ctx.parsed + ` (` + pct + `%)`;
            }
          }
        }
      }
    }
  });
</script>

</body>
</html>
"@

$html | Out-File $htmlFile -Encoding utf8 -Force
Write-Host "`nDashboard HTML generado: $htmlFile" -ForegroundColor Green

# ============================================================
# 15. PDF VÍA EDGE HEADLESS (comillas en rutas para espacios)
# ============================================================

try {
    $edgeArgs   = "--headless --disable-gpu --print-to-pdf=`"$pdfFile`" `"$htmlFile`""
    $edgeProc   = Start-Process "msedge.exe" -ArgumentList $edgeArgs -Wait -PassThru -ErrorAction Stop

    if (Test-Path $pdfFile) {
        Write-Host "PDF generado    : $pdfFile" -ForegroundColor Green
    } else {
        Write-Warning "Edge no generó el PDF (puede requerir ruta sin espacios)"
    }
} catch {
    Write-Warning "No se pudo generar PDF: $_"
}

# ============================================================
# 16. RESUMEN FINAL Y CIERRE
# ============================================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  FIN PROCESO  $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Cyan
Write-Host "  Apps        : $totalApps"
Write-Host "  Actualizadas: $actualizadas" -ForegroundColor Green
Write-Host "  Fallidas    : $fallidas"     -ForegroundColor Red
Write-Host "  Omitidas    : $omitCount"    -ForegroundColor Yellow
Write-Host "  Duración    : $($duration) min"
Write-Host "  Log         : $logFile"
Write-Host "========================================" -ForegroundColor Cyan

Stop-Transcript | Out-Null

Exit 0