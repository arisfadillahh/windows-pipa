Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$Root = 'C:\woa'
New-Item -ItemType Directory -Path $Root -Force | Out-Null
$LogPath = Join-Path $Root 'woa-dump.log'
"=== WOA DUMP START $(Get-Date -Format o) ===" | Set-Content -LiteralPath $LogPath -Encoding UTF8

function Run {
    param(
        [string]$File,
        [string[]]$ArgumentList,
        [string]$OutFile
    )
    $line = 'RUN {0} {1}' -f $File, ($ArgumentList -join ' ')
    $line | Tee-Object -FilePath $LogPath -Append
    $output = & $File @ArgumentList 2>&1
    $output | Tee-Object -FilePath $LogPath -Append
    if ($OutFile) {
        $output | Set-Content -LiteralPath (Join-Path $Root $OutFile) -Encoding UTF8
    }
    "EXIT $LASTEXITCODE" | Tee-Object -FilePath $LogPath -Append
}

Run -File pnputil.exe -ArgumentList @('/enum-devices', '/connected', '/deviceids', '/services') -OutFile 'devices-connected.txt'
Run -File pnputil.exe -ArgumentList @('/enum-devices', '/deviceids', '/services') -OutFile 'devices-all.txt'
Run -File sc.exe -ArgumentList @('query', 'type=', 'driver', 'state=', 'all') -OutFile 'driver-services.txt'
Run -File powershell.exe -ArgumentList @('-NoProfile', '-Command', 'Get-PnpDevice | Sort-Object Class,FriendlyName | Format-Table -AutoSize') -OutFile 'pnpdevice.txt'

if (Test-Path -LiteralPath 'C:\Windows\INF\setupapi.dev.log') {
    Get-Content -LiteralPath 'C:\Windows\INF\setupapi.dev.log' -Tail 500 |
        Set-Content -LiteralPath (Join-Path $Root 'setupapi-tail.txt') -Encoding UTF8
}

"=== WOA DUMP END $(Get-Date -Format o) ===" | Add-Content -LiteralPath $LogPath
Write-Host 'Dump done. Files are in C:\woa'
pause

