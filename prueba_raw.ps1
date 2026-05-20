_# 1. Forzar a que la sesión actual de PowerShell procese todo en UTF-8 limpio
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 2. Ensanchar el ancho de la consola en memoria para que Winget no recorte los nombres de las apps
if ($Host.UI.RawUI.BufferSize.Width -lt 500) {
    $newSize = $Host.UI.RawUI.BufferSize
    $newSize.Width = 500
    $Host.UI.RawUI.BufferSize = $newSize
}

# 3. Ejecutar la consulta de winget e inyectar el resultado directo en un TXT limpio
winget upgrade --include-unknown --accept-source-agreements --accept-package-agreements | Out-File -FilePath "C:\Scripts\prueba_raw.txt" -Encoding utf8

# 4. Abrir el archivo generado para inspección visual
notepad "C:\Scripts\prueba_raw.txt"