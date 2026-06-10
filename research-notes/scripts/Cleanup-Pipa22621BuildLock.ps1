[CmdletBinding()]
param(
    [int[]] $ProcessId = @(12120, 45708),
    [string] $BuildDir = 'D:\pipa-windows-build-22621'
)

$ErrorActionPreference = 'Continue'

$vhdx = Join-Path $BuildDir 'pipa-windows.vhdx'

Write-Host "[*] Cleaning stale pipa 22621 build locks"
foreach ($pidValue in $ProcessId) {
    $process = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
    if ($process) {
        Write-Host "[*] Stopping PID $pidValue ($($process.ProcessName))"
        Stop-Process -Id $pidValue -Force -ErrorAction Continue
    }
}

Start-Sleep -Seconds 2

try {
    Dismount-VHD -Path $vhdx -ErrorAction SilentlyContinue
} catch {
    Write-Warning $_.Exception.Message
}

if (Test-Path -LiteralPath $vhdx) {
    Write-Host "[*] Removing $vhdx"
    Remove-Item -LiteralPath $vhdx -Force -ErrorAction Continue
}

Write-Host "[*] Remaining build files:"
Get-ChildItem -LiteralPath $BuildDir -Force |
    Select-Object Name, Length, LastWriteTime |
    Format-Table -AutoSize

$drive = Get-PSDrive D
Write-Host ("[*] D: free space: {0:N2} GiB" -f ($drive.Free / 1GB))

