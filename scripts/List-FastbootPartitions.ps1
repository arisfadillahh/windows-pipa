[CmdletBinding()]
param(
    [string] $FastbootPath
)

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\Common.psm1" -Force

Assert-Windows

$fastboot = Resolve-LocalTool -Name 'fastboot' -ExplicitPath $FastbootPath

Write-Step "Fastboot device list"
Invoke-Native -FilePath $fastboot -Arguments @('devices')

Write-Step "Fastboot variables"
Invoke-Native -FilePath $fastboot -Arguments @('getvar', 'all') -AllowFailure
