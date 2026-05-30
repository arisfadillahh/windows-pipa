[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $WindowsIso,
    [string] $OutDir = '.\out\windows-image',
    [int] $DiskSizeGB = 80,
    [int] $EspSizeMB = 512,
    [int] $WindowsImageIndex = 1,
    [string] $DriverPath = '.\drivers\vendor',
    [switch] $SkipSparse,
    [switch] $CleanupIntermediates,
    [switch] $Force
)

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\Common.psm1" -Force

Assert-Windows
Assert-Admin

if (-not (Get-Command New-VHD -ErrorAction SilentlyContinue)) {
    throw "Hyper-V PowerShell cmdlets are required: New-VHD, Mount-VHD, Convert-VHD."
}

if (-not (Test-Path -LiteralPath $WindowsIso)) {
    throw "Windows ISO not found: $WindowsIso"
}

$repoRoot = Get-RepoRoot
if ([System.IO.Path]::IsPathRooted($OutDir)) {
    $resolvedOutDir = [System.IO.Path]::GetFullPath($OutDir)
} else {
    $resolvedOutDir = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $OutDir))
}
New-Item -ItemType Directory -Force -Path $resolvedOutDir | Out-Null

$vhdx = Join-Path $resolvedOutDir 'pipa-windows.vhdx'
$vhd = Join-Path $resolvedOutDir 'pipa-windows-fixed.vhd'
$sparse = Join-Path $resolvedOutDir 'pipa-windows-sparse.img'

if ((Test-Path -LiteralPath $vhdx) -or (Test-Path -LiteralPath $vhd) -or (Test-Path -LiteralPath $sparse)) {
    if (-not $Force) {
        throw "Output files already exist in $resolvedOutDir. Re-run with -Force to replace them."
    }
    Dismount-VHD -Path $vhdx -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $vhdx, $vhd, $sparse -Force -ErrorAction SilentlyContinue
}

Write-Step "Creating dynamic VHDX: $vhdx"
New-VHD -Path $vhdx -SizeBytes ($DiskSizeGB * 1GB) -Dynamic | Out-Null

$mountedIso = $null
$mountedVhd = $null
try {
    Write-Step "Mounting VHDX"
    $mountedVhd = Mount-VHD -Path $vhdx -PassThru
    $disk = $mountedVhd | Get-Disk
    Initialize-Disk -Number $disk.Number -PartitionStyle GPT

    Write-Step "Partitioning VHDX"
    $esp = New-Partition -DiskNumber $disk.Number -Size ($EspSizeMB * 1MB) -GptType '{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}' -AssignDriveLetter
    Format-Volume -Partition $esp -FileSystem FAT32 -NewFileSystemLabel 'ESP' -Confirm:$false | Out-Null
    $msr = New-Partition -DiskNumber $disk.Number -Size 16MB -GptType '{E3C9E316-0B5C-4DB8-817D-F92DF00215AE}'
    $windows = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter
    Format-Volume -Partition $windows -FileSystem NTFS -NewFileSystemLabel 'WINPIPA' -Confirm:$false | Out-Null

    $espRoot = "$($esp.DriveLetter):\"
    $windowsRoot = "$($windows.DriveLetter):\"

    Write-Step "Mounting Windows ISO"
    $mountedIso = Mount-DiskImage -ImagePath $WindowsIso -PassThru
    $isoVolume = $mountedIso | Get-Volume
    $isoRoot = "$($isoVolume.DriveLetter):\"
    $imageFile = Get-WindowsImageFile -IsoRoot $isoRoot

    Write-Step "Applying Windows image index $WindowsImageIndex"
    Invoke-Native -FilePath 'dism.exe' -Arguments @(
        '/Apply-Image',
        "/ImageFile:$imageFile",
        "/Index:$WindowsImageIndex",
        "/ApplyDir:$windowsRoot"
    )

    if ($DriverPath -and (Test-Path -LiteralPath $DriverPath)) {
        $resolvedDriverPath = (Resolve-Path -LiteralPath $DriverPath).Path
        $driverInfs = Get-ChildItem -LiteralPath $resolvedDriverPath -Recurse -Filter *.inf -File -ErrorAction SilentlyContinue
        if ($driverInfs) {
            Write-Step "Injecting drivers from $resolvedDriverPath"
            Invoke-Native -FilePath 'dism.exe' -Arguments @(
                "/Image:$windowsRoot",
                '/Add-Driver',
                "/Driver:$resolvedDriverPath",
                '/Recurse'
            )
        } else {
            Write-Warn "No .inf drivers found in $resolvedDriverPath"
        }
    }

    Write-Step "Creating UEFI boot files"
    Invoke-Native -FilePath 'bcdboot.exe' -Arguments @(
        (Join-Path $windowsRoot 'Windows'),
        '/s',
        $espRoot,
        '/f',
        'UEFI'
    )

    $bcdPath = Join-Path $espRoot 'EFI\Microsoft\Boot\BCD'
    Invoke-Native -FilePath 'bcdedit.exe' -Arguments @('/store', $bcdPath, '/set', '{default}', 'testsigning', 'on') -AllowFailure

    Write-Step "Applying offline USB/OOBE registry tweaks"
    $systemHive = Join-Path $windowsRoot 'Windows\System32\config\SYSTEM'
    $softwareHive = Join-Path $windowsRoot 'Windows\System32\config\SOFTWARE'
    Invoke-Native -FilePath 'reg.exe' -Arguments @('load', 'HKLM\PIPA_SYSTEM', $systemHive) -AllowFailure
    try {
        Invoke-Native -FilePath 'reg.exe' -Arguments @('add', 'HKLM\PIPA_SYSTEM\ControlSet001\Control\USB', '/v', 'OsDefaultRoleSwitchMode', '/t', 'REG_DWORD', '/d', '1', '/f') -AllowFailure
    } finally {
        Invoke-Native -FilePath 'reg.exe' -Arguments @('unload', 'HKLM\PIPA_SYSTEM') -AllowFailure
    }

    Invoke-Native -FilePath 'reg.exe' -Arguments @('load', 'HKLM\PIPA_SOFTWARE', $softwareHive) -AllowFailure
    try {
        Invoke-Native -FilePath 'reg.exe' -Arguments @('add', 'HKLM\PIPA_SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE', '/v', 'LaunchUserOOBE', '/t', 'REG_DWORD', '/d', '0', '/f') -AllowFailure
        Invoke-Native -FilePath 'reg.exe' -Arguments @('add', 'HKLM\PIPA_SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE', '/v', 'DefaultAccountAction', '/t', 'REG_DWORD', '/d', '0', '/f') -AllowFailure
        Invoke-Native -FilePath 'reg.exe' -Arguments @('add', 'HKLM\PIPA_SOFTWARE\Policies\Microsoft\Windows\OOBE', '/v', 'DisablePrivacyExperience', '/t', 'REG_DWORD', '/d', '1', '/f') -AllowFailure
    } finally {
        Invoke-Native -FilePath 'reg.exe' -Arguments @('unload', 'HKLM\PIPA_SOFTWARE') -AllowFailure
    }
} finally {
    if ($mountedIso) {
        Dismount-DiskImage -ImagePath $WindowsIso -ErrorAction SilentlyContinue | Out-Null
    }
    if ($mountedVhd) {
        Dismount-VHD -Path $vhdx -ErrorAction SilentlyContinue
    }
}

Write-Step "Converting VHDX to fixed VHD"
Convert-VHD -Path $vhdx -DestinationPath $vhd -VHDType Fixed

if ($CleanupIntermediates) {
    Write-Step "Removing intermediate VHDX"
    Remove-Item -LiteralPath $vhdx -Force -ErrorAction SilentlyContinue
}

if (-not $SkipSparse) {
    Write-Step "Converting fixed VHD to Android sparse image"
    python (Join-Path $PSScriptRoot 'ConvertTo-AndroidSparseImage.py') `
        --input $vhd `
        --output $sparse `
        --strip-trailing-bytes 512

    if ($CleanupIntermediates) {
        Write-Step "Removing intermediate fixed VHD"
        Remove-Item -LiteralPath $vhd -Force -ErrorAction SilentlyContinue
    }
}

Write-Step "Build complete"
if (Test-Path -LiteralPath $vhdx) {
    Write-Host "VHDX: $vhdx"
}
if (Test-Path -LiteralPath $vhd) {
    Write-Host "Fixed VHD: $vhd"
}
if (-not $SkipSparse) {
    Write-Host "Sparse flash image: $sparse"
}
