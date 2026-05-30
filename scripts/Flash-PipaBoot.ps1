[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $UefiImage,
    [Parameter(Mandatory)] [ValidateSet('a', 'b')] [string] $BootSlot,
    [string] $FastbootPath,
    [switch] $NoSetActive,
    [switch] $AllowDestructive,
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\Common.psm1" -Force

Assert-Windows

if (-not (Test-Path -LiteralPath $UefiImage)) {
    throw "UEFI image not found: $UefiImage"
}

Confirm-Destructive -AllowDestructive:$AllowDestructive.IsPresent -Message "Flashing boot_$BootSlot can make that slot unbootable if the image is wrong."

$fastboot = Resolve-LocalTool -Name 'fastboot' -ExplicitPath $FastbootPath
$resolvedImage = (Resolve-Path -LiteralPath $UefiImage).Path
$targetPartition = "boot_$BootSlot"

Write-Step "Checking fastboot device"
Invoke-Native -FilePath $fastboot -Arguments @('devices') -DryRun:$DryRun
Invoke-Native -FilePath $fastboot -Arguments @('getvar', 'product') -AllowFailure -DryRun:$DryRun
Invoke-Native -FilePath $fastboot -Arguments @('getvar', 'current-slot') -AllowFailure -DryRun:$DryRun
Invoke-Native -FilePath $fastboot -Arguments @('getvar', 'unlocked') -AllowFailure -DryRun:$DryRun

Write-Warn "Target boot partition: $targetPartition"
Write-Warn "Make sure this is the Linux/postmarketOS slot, not the Android slot."

Write-Step "Flashing UEFI image"
Invoke-Native -FilePath $fastboot -Arguments @('flash', $targetPartition, $resolvedImage) -DryRun:$DryRun

if (-not $NoSetActive) {
    Write-Step "Setting active slot to $BootSlot"
    Invoke-Native -FilePath $fastboot -Arguments @('set_active', $BootSlot) -DryRun:$DryRun
}

Write-Step "Done. Reboot manually after reviewing fastboot output."
