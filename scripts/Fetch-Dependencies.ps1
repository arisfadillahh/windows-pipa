[CmdletBinding()]
param(
    [string] $PlatformToolsUrl = 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip',
    [switch] $Force
)

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\Common.psm1" -Force

Assert-Windows

$repoRoot = Get-RepoRoot
$toolsDir = Join-Path $repoRoot 'tools'
$platformToolsDir = Join-Path $toolsDir 'platform-tools'
$zipPath = Join-Path $toolsDir 'platform-tools-latest-windows.zip'

New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null

if ((Test-Path -LiteralPath (Join-Path $platformToolsDir 'adb.exe')) -and -not $Force) {
    Write-Step "Android platform-tools already available at $platformToolsDir"
} else {
    Write-Step "Downloading Android platform-tools"
    Invoke-WebRequest -Uri $PlatformToolsUrl -OutFile $zipPath

    if (Test-Path -LiteralPath $platformToolsDir) {
        Remove-Item -LiteralPath $platformToolsDir -Recurse -Force
    }

    Expand-Archive -LiteralPath $zipPath -DestinationPath $toolsDir -Force
    Remove-Item -LiteralPath $zipPath -Force
    Write-Step "Installed platform-tools to $platformToolsDir"
}

Write-Host ""
Write-Host "Manual inputs still required:"
Write-Host "- Official Windows ARM64 ISO from https://www.microsoft.com/en-us/software-download/windows11arm64"
Write-Host "- Tested pipa UEFI image, for example firmware\Mu-pipa.img"
