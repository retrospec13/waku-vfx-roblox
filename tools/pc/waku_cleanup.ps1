# waku_cleanup.ps1 - close ONLY our Studio (pid from owner.json, verified by its command line naming our build folder)
# and delete our task. Other Studio windows are listed, never touched.
$Root = Split-Path -Parent $PSScriptRoot
$o = Get-Content -LiteralPath "$Root\owner.json" -Raw | ConvertFrom-Json
"before:"; Get-CimInstance Win32_Process -Filter "Name='RobloxStudioBeta.exe'" | ForEach-Object { "  {0} {1}" -f $_.ProcessId, $_.CommandLine }
$p = Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f $o.pid)
if ($p -and $p.CommandLine -like "*$Root\build\*") { Stop-Process -Id $o.pid -Force; "stopped owned pid $($o.pid)" } else { "owned pid $($o.pid) not running or not ours: nothing closed" }
Unregister-ScheduledTask -TaskName 'WAKUVFX_launch' -Confirm:$false -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
"after:"; Get-CimInstance Win32_Process -Filter "Name='RobloxStudioBeta.exe'" | ForEach-Object { "  {0} {1}" -f $_.ProcessId, $_.CommandLine }
"task WAKUVFX_launch present: " + [bool](Get-ScheduledTask -TaskName 'WAKUVFX_launch' -ErrorAction SilentlyContinue)
