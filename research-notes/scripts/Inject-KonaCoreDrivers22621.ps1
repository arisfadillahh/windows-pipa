[CmdletBinding()]
param(
    [string] $Vhdx = 'D:\pipa-windows-build-22621-4kn\pipa-windows.vhdx',
    [string] $DriverStage = 'D:\pipa-drivers\kona-core-staged-20260531',
    [string] $BuildDir = 'D:\pipa-windows-build-22621-4kn',
    [string] $RepoRoot = '<LEGACY_WORKSPACE>',
    [string] $LogPath = 'D:\pipa-windows-build-22621-4kn\inject-kona-core.log'
)

$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string] $Message)
    $stamp = Get-Date -Format o
    Add-Content -LiteralPath $LogPath -Value "[$stamp] $Message" -Encoding ASCII
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

function Add-RegDword {
    param(
        [string] $Path,
        [string] $Name,
        [int] $Value
    )
    New-Item -Path $Path -Force | Out-Null
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
    Write-Log "REG DWORD $Path $Name=$Value"
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath) | Out-Null
Remove-Item -LiteralPath $LogPath -Force -ErrorAction SilentlyContinue

Write-Log '[START] Kona core driver injection'
Write-Log "[INPUT] Vhdx=$Vhdx"
Write-Log "[INPUT] DriverStage=$DriverStage"
Write-Log "[INPUT] BuildDir=$BuildDir"
Write-Log "[INPUT] RepoRoot=$RepoRoot"

Assert-Admin

Invoke-Logged -FilePath 'reg.exe' -Arguments @('unload', 'HKLM\PIPA_SYSTEM_KONA') -ContinueOnError | Out-Null
Invoke-Logged -FilePath 'reg.exe' -Arguments @('unload', 'HKLM\PIPA_SOFTWARE_KONA') -ContinueOnError | Out-Null

if (-not (Test-Path -LiteralPath $Vhdx)) {
    throw "VHDX not found: $Vhdx"
}
if (-not (Test-Path -LiteralPath $DriverStage)) {
    throw "Driver stage not found: $DriverStage"
}
if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot 'scripts\Extract-Pipa22621-4KnFromVhdx.ps1'))) {
    throw "Extractor script not found under RepoRoot: $RepoRoot"
}
if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot 'scripts\FatFileInImage.py'))) {
    throw "FAT image helper not found under RepoRoot: $RepoRoot"
}

$mounted = $null
$dismLog = Join-Path $BuildDir 'dism-kona-core.log'
$successFile = Join-Path $BuildDir 'kona-core-drivers-success.txt'
$failureFile = Join-Path $BuildDir 'kona-core-drivers-failed.txt'
Remove-Item -LiteralPath $dismLog, $successFile, $failureFile -Force -ErrorAction SilentlyContinue

try {
    $existing = Get-DiskImage -ImagePath $Vhdx -ErrorAction SilentlyContinue
    if ($existing -and $existing.Attached) {
        Write-Log '[VHDX] Already attached, dismounting before read-write mount'
        Dismount-VHD -Path $Vhdx -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    Write-Log '[VHDX] Mounting read-write'
    $mounted = Mount-VHD -Path $Vhdx -PassThru
    $disk = $mounted | Get-Disk
    Write-Log "[DISK] number=$($disk.Number) logical_sector=$($disk.LogicalSectorSize) physical_sector=$($disk.PhysicalSectorSize)"

    $partitions = Get-Partition -DiskNumber $disk.Number | Sort-Object Offset
    foreach ($partition in $partitions) {
        Write-Log "[PART] number=$($partition.PartitionNumber) type=$($partition.Type) size=$($partition.Size) offset=$($partition.Offset) letter=$($partition.DriveLetter)"
    }

    $windows = $partitions | Sort-Object Size -Descending | Select-Object -First 1
    if (-not $windows) {
        throw 'Windows partition not found in VHDX.'
    }
    if (-not $windows.DriveLetter) {
        Write-Log "[PART] Assigning drive letter to partition $($windows.PartitionNumber)"
        Add-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $windows.PartitionNumber -AssignDriveLetter
        $windows = Get-Partition -DiskNumber $disk.Number -PartitionNumber $windows.PartitionNumber
    }

    $windowsRoot = "$($windows.DriveLetter):\"
    if (-not (Test-Path -LiteralPath (Join-Path $windowsRoot 'Windows\System32\config\SYSTEM'))) {
        throw "Mounted partition does not look like Windows root: $windowsRoot"
    }
    Write-Log "[WINDOWS] root=$windowsRoot"

    $infFiles = Get-ChildItem -LiteralPath $DriverStage -Recurse -Filter *.inf -File | Sort-Object FullName
    Write-Log "[DRIVERS] candidate_inf_count=$($infFiles.Count)"
    $success = New-Object System.Collections.Generic.List[string]
    $failed = New-Object System.Collections.Generic.List[string]

    foreach ($inf in $infFiles) {
        $relative = $inf.FullName.Substring($DriverStage.Length + 1)
        Write-Log "[DRIVER] Adding $relative"
        $code = Invoke-Logged -FilePath 'dism.exe' -Arguments @(
            "/Image:$windowsRoot",
            '/Add-Driver',
            "/Driver:$($inf.FullName)",
            '/ForceUnsigned',
            "/LogPath:$dismLog"
        ) -ContinueOnError
        if ($code -eq 0) {
            $success.Add($relative) | Out-Null
        } else {
            $failed.Add("$relative exit=$code") | Out-Null
        }
    }

    $success | Set-Content -LiteralPath $successFile -Encoding ASCII
    $failed | Set-Content -LiteralPath $failureFile -Encoding ASCII
    Write-Log "[DRIVERS] success=$($success.Count) failed=$($failed.Count)"

    Write-Log '[REG] Applying offline SYSTEM tweaks'
    $systemHive = Join-Path $windowsRoot 'Windows\System32\config\SYSTEM'
    Invoke-Logged -FilePath 'reg.exe' -Arguments @('load', 'HKLM\PIPA_SYSTEM_KONA', $systemHive)
    try {
        $controlSets = Get-ChildItem -Path 'Registry::HKEY_LOCAL_MACHINE\PIPA_SYSTEM_KONA' |
            Where-Object { $_.PSChildName -like 'ControlSet*' }
        foreach ($controlSet in $controlSets) {
            $base = "Registry::HKEY_LOCAL_MACHINE\PIPA_SYSTEM_KONA\$($controlSet.PSChildName)"
            Add-RegDword -Path (Join-Path $base 'Control\USB') -Name 'OsDefaultRoleSwitchMode' -Value 1
            Add-RegDword -Path (Join-Path $base 'Control\CrashControl') -Name 'AutoReboot' -Value 0
            Add-RegDword -Path (Join-Path $base 'Control\CrashControl') -Name 'DisplayParameters' -Value 1
        }
    } finally {
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
        Invoke-Logged -FilePath 'reg.exe' -Arguments @('unload', 'HKLM\PIPA_SYSTEM_KONA') -ContinueOnError | Out-Null
    }

    Write-Log '[REG] Applying offline SOFTWARE OOBE tweaks'
    $softwareHive = Join-Path $windowsRoot 'Windows\System32\config\SOFTWARE'
    Invoke-Logged -FilePath 'reg.exe' -Arguments @('load', 'HKLM\PIPA_SOFTWARE_KONA', $softwareHive)
    try {
        Add-RegDword -Path 'Registry::HKEY_LOCAL_MACHINE\PIPA_SOFTWARE_KONA\Microsoft\Windows\CurrentVersion\OOBE' -Name 'LaunchUserOOBE' -Value 0
        Add-RegDword -Path 'Registry::HKEY_LOCAL_MACHINE\PIPA_SOFTWARE_KONA\Microsoft\Windows\CurrentVersion\OOBE' -Name 'DefaultAccountAction' -Value 0
        Add-RegDword -Path 'Registry::HKEY_LOCAL_MACHINE\PIPA_SOFTWARE_KONA\Policies\Microsoft\Windows\OOBE' -Name 'DisablePrivacyExperience' -Value 1
    } finally {
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
        Invoke-Logged -FilePath 'reg.exe' -Arguments @('unload', 'HKLM\PIPA_SOFTWARE_KONA') -ContinueOnError | Out-Null
    }
} finally {
    if ($mounted) {
        Write-Log '[VHDX] Dismounting after injection'
        Dismount-VHD -Path $Vhdx -ErrorAction SilentlyContinue
    }
}

Write-Log '[EXTRACT] Re-extracting ESP and Windows sparse from updated VHDX'
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

Write-Log '[BCD] Switching Windows loader device/osdevice to locate'
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

Write-Log '[DONE] Kona core driver injection and image extraction complete'
Write-Log "[OUTPUT] ESP=$espImage"
Write-Log "[OUTPUT] WINDOWS=$(Join-Path $BuildDir 'windows-only-22621-4kn.sparse.img')"
Write-Log "[OUTPUT] DriverSuccess=$successFile"
Write-Log "[OUTPUT] DriverFailed=$failureFile"

