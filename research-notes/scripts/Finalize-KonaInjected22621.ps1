[CmdletBinding()]
param(
    [string] $Vhdx = 'D:\pipa-windows-build-22621-4kn\pipa-windows.vhdx',
    [string] $BuildDir = 'D:\pipa-windows-build-22621-4kn',
    [string] $RepoRoot = '<LEGACY_WORKSPACE>',
    [string] $LogPath = 'D:\pipa-windows-build-22621-4kn\finalize-kona-injected.log'
)

$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string] $Message)
    Add-Content -LiteralPath $LogPath -Value "[$(Get-Date -Format o)] $Message" -Encoding ASCII
}

function Invoke-Logged {
    param(
        [string] $FilePath,
        [string[]] $Arguments,
        [switch] $ContinueOnError
    )
    Write-Log ("> {0} {1}" -f $FilePath, ($Arguments -join ' '))
    $output = & $FilePath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    foreach ($line in $output) {
        Add-Content -LiteralPath $LogPath -Value $line -Encoding ASCII
    }
    Write-Log "[exit] $FilePath => $exitCode"
    if ($exitCode -ne 0 -and -not $ContinueOnError) {
        throw "$FilePath exited with code $exitCode"
    }
    return [int] $exitCode
}

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'This script must run elevated.'
    }
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath) | Out-Null
Remove-Item -LiteralPath $LogPath -Force -ErrorAction SilentlyContinue
Write-Log '[START] Finalize Kona-injected 22621 images'

Assert-Admin

Invoke-Logged -FilePath 'reg.exe' -Arguments @('unload', 'HKLM\PIPA_SYSTEM_KONA') -ContinueOnError | Out-Null
Invoke-Logged -FilePath 'reg.exe' -Arguments @('unload', 'HKLM\PIPA_SOFTWARE_KONA') -ContinueOnError | Out-Null

if (-not (Test-Path -LiteralPath $Vhdx)) {
    throw "VHDX not found: $Vhdx"
}
if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot 'scripts\Extract-Pipa22621-4KnFromVhdx.ps1'))) {
    throw "Extractor script not found under RepoRoot: $RepoRoot"
}
if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot 'scripts\FatFileInImage.py'))) {
    throw "FAT image helper not found under RepoRoot: $RepoRoot"
}

$existing = Get-DiskImage -ImagePath $Vhdx -ErrorAction SilentlyContinue
if ($existing -and $existing.Attached) {
    Write-Log '[VHDX] Dismounting stale attachment before extraction'
    Dismount-VHD -Path $Vhdx -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

Write-Log '[EXTRACT] Re-extracting ESP and Windows sparse'
Invoke-Logged -FilePath 'powershell.exe' -Arguments @(
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    (Join-Path $RepoRoot 'scripts\Extract-Pipa22621-4KnFromVhdx.ps1'),
    '-Vhdx',
    $Vhdx,
    '-OutDir',
    $BuildDir
)

$espImage = Join-Path $BuildDir 'esp-22621-4kn.raw.img'
$windowsSparse = Join-Path $BuildDir 'windows-only-22621-4kn.sparse.img'
$workDir = Join-Path $BuildDir 'bcd-locate-patch-4kn'
$bcd = Join-Path $workDir 'BCD'
$before = Join-Path $workDir 'bcd-before.txt'
$after = Join-Path $workDir 'bcd-after.txt'
New-Item -ItemType Directory -Force -Path $workDir | Out-Null
Remove-Item -LiteralPath $bcd, $before, $after -Force -ErrorAction SilentlyContinue

Write-Log '[BCD] Extracting BCD from ESP image'
Invoke-Logged -FilePath 'python' -Arguments @(
    (Join-Path $RepoRoot 'scripts\FatFileInImage.py'),
    'extract',
    '--image',
    $espImage,
    '--path',
    '/EFI/Microsoft/Boot/BCD',
    '--output',
    $bcd
)

& bcdedit.exe /store $bcd /enum all /v 2>&1 | Set-Content -LiteralPath $before -Encoding ASCII

Write-Log '[BCD] Setting loader to locate mode'
Invoke-Logged -FilePath 'bcdedit.exe' -Arguments @('/store', $bcd, '/set', '{default}', 'device', 'locate')
Invoke-Logged -FilePath 'bcdedit.exe' -Arguments @('/store', $bcd, '/set', '{default}', 'osdevice', 'locate')
Invoke-Logged -FilePath 'bcdedit.exe' -Arguments @('/store', $bcd, '/set', '{default}', 'path', '\Windows\system32\winload.efi')
Invoke-Logged -FilePath 'bcdedit.exe' -Arguments @('/store', $bcd, '/set', '{default}', 'systemroot', '\Windows')
Invoke-Logged -FilePath 'bcdedit.exe' -Arguments @('/store', $bcd, '/set', '{default}', 'testsigning', 'on')
Invoke-Logged -FilePath 'bcdedit.exe' -Arguments @('/store', $bcd, '/set', '{default}', 'recoveryenabled', 'no')
Invoke-Logged -FilePath 'bcdedit.exe' -Arguments @('/store', $bcd, '/set', '{default}', 'bootstatuspolicy', 'IgnoreAllFailures') -ContinueOnError | Out-Null
Invoke-Logged -FilePath 'bcdedit.exe' -Arguments @('/store', $bcd, '/set', '{bootmgr}', 'timeout', '3') -ContinueOnError | Out-Null

& bcdedit.exe /store $bcd /enum all /v 2>&1 | Set-Content -LiteralPath $after -Encoding ASCII

Write-Log '[BCD] Replacing BCD inside ESP image'
Invoke-Logged -FilePath 'python' -Arguments @(
    (Join-Path $RepoRoot 'scripts\FatFileInImage.py'),
    'replace',
    '--image',
    $espImage,
    '--path',
    '/EFI/Microsoft/Boot/BCD',
    '--input',
    $bcd
)

Write-Log '[DONE] Finalize complete'
Write-Log "[OUTPUT] ESP=$espImage"
Write-Log "[OUTPUT] WINDOWS=$windowsSparse"

