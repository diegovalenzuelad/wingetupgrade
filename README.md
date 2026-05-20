# wingetupgrade
=================================================================================================
Esta tarea es un tema especial para llevar control de actualizaciones de Windows mediante winget.

La programación de tareas se debe generar con los niveles más altos y en con un perfil de usuario
administrador o con SYSTEM.


$Action = New-ScheduledTaskAction `
  -Execute "powershell.exe" `
  -Argument "-NoProfile -ExecutionPolicy Bypass -File `"C:\Scripts\winget-upgrade-report.ps1`""

$Trigger = New-ScheduledTaskTrigger `
  -Weekly `
  -DaysOfWeek Monday `
  -At 09:00

$Principal = New-ScheduledTaskPrincipal `
  -UserId "SYSTEM" `
  -LogonType ServiceAccount `
  -RunLevel Highest

Register-ScheduledTask `
  -TaskName "Winget Weekly Upgrade + PDF Report" `
  -Action $Action `
  -Trigger $Trigger `
  -Principal $Principal `
  -Description "Actualización semanal de aplicaciones vía winget con reporte PDF"


=================================================================================================
