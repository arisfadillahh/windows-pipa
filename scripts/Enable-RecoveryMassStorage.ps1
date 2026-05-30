[CmdletBinding()]
param(
    [string] $AdbPath,
    [switch] $SkipReboot,
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\Common.psm1" -Force

Assert-Windows

$adb = Resolve-LocalTool -Name 'adb' -ExplicitPath $AdbPath

if (-not $SkipReboot) {
    Write-Step "Rebooting tablet to recovery"
    Invoke-Native -FilePath $adb -Arguments @('reboot', 'recovery') -DryRun:$DryRun
    if (-not $DryRun) {
        Start-Sleep -Seconds 10
        Invoke-Native -FilePath $adb -Arguments @('wait-for-device') -AllowFailure
    }
}

Write-Step "Trying common recovery mass-storage hook"
Invoke-Native -FilePath $adb -Arguments @('shell', 'setenforce', '0') -AllowFailure -DryRun:$DryRun
Invoke-Native -FilePath $adb -Arguments @('shell', 'msc.sh') -AllowFailure -DryRun:$DryRun

Write-Warn "If no new Windows drives appear, your recovery does not expose msc.sh."
Write-Warn "Use your existing postmarketOS/recovery method to expose the Linux and ESP partitions."
