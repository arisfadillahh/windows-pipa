[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $WindowsSparseImage,
    [Parameter(Mandatory)] [string] $UefiBootImage,
    [ValidateSet('a', 'b')] [string] $WindowsSlot = 'b',
    [string] $FastbootPath,
    [switch] $AllowDestructive,
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\Common.psm1" -Force

Assert-Windows
Confirm-Destructive -AllowDestructive:$AllowDestructive.IsPresent -Message "This will overwrite the pipa linux partition and boot_$WindowsSlot."

if (-not (Test-Path -LiteralPath $WindowsSparseImage)) {
    throw "Windows sparse image not found: $WindowsSparseImage"
}

if (-not (Test-Path -LiteralPath $UefiBootImage)) {
    throw "UEFI boot image not found: $UefiBootImage"
}

$fastboot = Resolve-LocalTool -Name 'fastboot' -ExplicitPath $FastbootPath
$windowsImage = (Resolve-Path -LiteralPath $WindowsSparseImage).Path
$uefiImage = (Resolve-Path -LiteralPath $UefiBootImage).Path

Write-Step "Checking fastboot device"
Invoke-Native -FilePath $fastboot -Arguments @('devices') -DryRun:$DryRun
Invoke-Native -FilePath $fastboot -Arguments @('getvar', 'product') -AllowFailure -DryRun:$DryRun
Invoke-Native -FilePath $fastboot -Arguments @('getvar', 'current-slot') -AllowFailure -DryRun:$DryRun

Write-Step "Flashing Windows disk image to by-name linux partition"
Invoke-Native -FilePath $fastboot -Arguments @('flash', 'linux', $windowsImage) -DryRun:$DryRun

Write-Step "Flashing UEFI boot image to boot_$WindowsSlot"
Invoke-Native -FilePath $fastboot -Arguments @('flash', "boot_$WindowsSlot", $uefiImage) -DryRun:$DryRun

Write-Step "Setting active slot to $WindowsSlot"
Invoke-Native -FilePath $fastboot -Arguments @('set_active', $WindowsSlot) -DryRun:$DryRun

Write-Step "Rebooting"
Invoke-Native -FilePath $fastboot -Arguments @('reboot') -DryRun:$DryRun

