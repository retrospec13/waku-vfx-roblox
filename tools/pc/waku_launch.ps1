# waku_launch.ps1 - launch this project's Studio place from build\<place>.rbxlx.
# Runs inside the interactive scheduled task WAKUVFX_launch (console session). Refuses if our recorded pid is alive.
# Writes owner.json {pid, path, exe, utc}. Never touches other Studio windows, AutoSaves or tasks.
param([string]$PlaceName = 'wakuvfx_dev.rbxlx')
$Root = Split-Path -Parent $PSScriptRoot
$Place = "$Root\build\$PlaceName"
$Owner = "$Root\owner.json"
$Log = "$Root\launch.log"
function Say($m) { $l = "{0} {1}" -f (Get-Date).ToUniversalTime().ToString('o'), $m; Add-Content -LiteralPath $Log -Value $l; Write-Output $l }
if (-not (Test-Path -LiteralPath $Place)) { Say "NO_PLACE $Place"; exit 5 }
if (Test-Path -LiteralPath $Owner) {
    $o = Get-Content -LiteralPath $Owner -Raw | ConvertFrom-Json
    $p = Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f $o.pid) -ErrorAction SilentlyContinue
    if ($p -and $p.CommandLine -like "*$Root\build\*") { Say "REFUSE pid $($o.pid) still running our place"; exit 4 }
}
$exe = @(Get-ChildItem "$env:LOCALAPPDATA\Roblox\Versions\*\RobloxStudioBeta.exe" -ErrorAction SilentlyContinue) | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $exe) { Say 'NO_STUDIO_EXE'; exit 6 }
$t0 = (Get-Date).ToUniversalTime()
$proc = Start-Process -FilePath $exe.FullName -ArgumentList ('"{0}"' -f $Place) -PassThru
[ordered]@{ pid = $proc.Id; path = $Place; exe = $exe.FullName; utc = $t0.ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $Owner -Encoding ASCII
Say ("LAUNCHED pid={0} exe={1} place={2}" -f $proc.Id, $exe.FullName, $Place)
