# waku_task.ps1 [place] - (re)register and run the interactive scheduled task WAKUVFX_launch (console session).
param([string]$PlaceName = 'wakuvfx_dev.rbxlx')
$Root = Split-Path -Parent $PSScriptRoot
$user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Root\tools\waku_launch.ps1`" -PlaceName $PlaceName"
$pr = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName 'WAKUVFX_launch' -Action $act -Principal $pr -Force | Out-Null
Start-ScheduledTask -TaskName 'WAKUVFX_launch'
Start-Sleep -Seconds 4
Get-Content -LiteralPath "$Root\launch.log" -Tail 3
