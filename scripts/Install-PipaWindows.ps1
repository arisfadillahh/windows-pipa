[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $WindowsIso,
    [Parameter(Mandatory)] [string] $WindowsDrive,
    [Parameter(Mandatory)] [string] $EspDrive,
    [int] $WindowsImageIndex = 1,
    [string] $DriverPath,
    [switch] $FormatWindowsDrive,
    [switch] $FormatEspDrive,
    [switch] $SkipUnattend,
    [switch] $AllowDestructive,
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\Common.psm1" -Force

Assert-Windows
Assert-Admin

if (-not (Test-Path -LiteralPath $WindowsIso)) {
    throw "Windows ISO not found: $WindowsIso"
}

$windowsRoot = ConvertTo-DriveRoot -Drive $WindowsDrive
$espRoot = ConvertTo-DriveRoot -Drive $EspDrive
$windowsLetter = Get-DriveLetterOnly -Drive $WindowsDrive
$espLetter = Get-DriveLetterOnly -Drive $EspDrive

if ($windowsLetter -eq $espLetter) {
    throw "WindowsDrive and EspDrive must be different."
}

if (-not (Test-Path -LiteralPath $windowsRoot)) {
    throw "Windows target drive does not exist: $windowsRoot"
}

if (-not (Test-Path -LiteralPath $espRoot)) {
    throw "ESP drive does not exist: $espRoot"
}

Write-Step "Windows target: $windowsRoot"
Write-Step "ESP target: $espRoot"

if ($FormatWindowsDrive -or $FormatEspDrive) {
    Confirm-Destructive -AllowDestructive:$AllowDestructive.IsPresent -Message "Formatting selected partitions is destructive."
}

if (-not $DryRun) {
    $winVol = Get-Volume -DriveLetter $windowsLetter
    $espVol = Get-Volume -DriveLetter $espLetter
    Write-Step "Windows volume before install: $($winVol.FileSystemLabel) $($winVol.FileSystem) $([math]::Round($winVol.Size / 1GB, 2))GB"
    Write-Step "ESP volume before install: $($espVol.FileSystemLabel) $($espVol.FileSystem) $([math]::Round($espVol.Size / 1MB, 0))MB"
}

if ($DryRun) {
    Write-Step "Dry run only. No format, DISM, BCD, registry, or driver changes will be made."
    return
}

if ($FormatWindowsDrive) {
    Write-Step "Formatting $windowsLetter as NTFS"
    Format-Volume -DriveLetter $windowsLetter -FileSystem NTFS -NewFileSystemLabel 'WINPIPA' -Confirm:$false | Out-Null
}

if ($FormatEspDrive) {
    Write-Step "Formatting $espLetter as FAT32"
    Format-Volume -DriveLetter $espLetter -FileSystem FAT32 -NewFileSystemLabel 'ESP' -Confirm:$false | Out-Null
}

$mountedImage = $null
try {
    Write-Step "Mounting Windows ISO"
    $mountedImage = Mount-DiskImage -ImagePath $WindowsIso -PassThru
    $isoVolume = $mountedImage | Get-Volume
    $isoRoot = "$($isoVolume.DriveLetter):\"
    $imageFile = Get-WindowsImageFile -IsoRoot $isoRoot

    Write-Step "Applying Windows image index $WindowsImageIndex"
    Invoke-Native -FilePath 'dism.exe' -Arguments @(
        '/Apply-Image',
        "/ImageFile:$imageFile",
        "/Index:$WindowsImageIndex",
        "/ApplyDir:$windowsRoot"
    )

    if ($DriverPath) {
        if (-not (Test-Path -LiteralPath $DriverPath)) {
            throw "DriverPath not found: $DriverPath"
        }

        $resolvedDriverPath = (Resolve-Path -LiteralPath $DriverPath).Path
        $driverInfs = Get-ChildItem -LiteralPath $resolvedDriverPath -Recurse -Filter *.inf -File -ErrorAction SilentlyContinue
        if (-not $driverInfs) {
            Write-Warn "No .inf files found under $resolvedDriverPath; skipping driver injection."
        } else {
        Write-Step "Injecting drivers from $resolvedDriverPath"
        Invoke-Native -FilePath 'dism.exe' -Arguments @(
            "/Image:$windowsRoot",
            '/Add-Driver',
            "/Driver:$resolvedDriverPath",
            '/Recurse'
        )
        }
    }

    Write-Step "Creating UEFI boot files"
    $windowsDir = Join-Path $windowsRoot 'Windows'
    Invoke-Native -FilePath 'bcdboot.exe' -Arguments @(
        $windowsDir,
        '/s',
        $espRoot,
        '/f',
        'UEFI'
    )

    Write-Step "Enabling test signing in offline BCD"
    $bcdPath = Join-Path $espRoot 'EFI\Microsoft\Boot\BCD'
    Invoke-Native -FilePath 'bcdedit.exe' -Arguments @(
        '/store',
        $bcdPath,
        '/set',
        '{default}',
        'testsigning',
        'on'
    ) -AllowFailure

    if (-not $SkipUnattend) {
        Write-Step "Writing minimal unattend file"
        $pantherDir = Join-Path $windowsRoot 'Windows\Panther'
        New-Item -ItemType Directory -Force -Path $pantherDir | Out-Null
        $unattendPath = Join-Path $pantherDir 'Unattend.xml'
        @'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core" processorArchitecture="arm64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <InputLocale>en-US</InputLocale>
      <SystemLocale>en-US</SystemLocale>
      <UILanguage>en-US</UILanguage>
      <UserLocale>en-US</UserLocale>
    </component>
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="arm64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideLocalAccountScreen>false</HideLocalAccountScreen>
        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>
    </component>
  </settings>
</unattend>
'@ | Set-Content -LiteralPath $unattendPath -Encoding UTF8
    }

    Write-Step "Install image is ready"
} finally {
    if ($mountedImage) {
        Write-Step "Dismounting Windows ISO"
        Dismount-DiskImage -ImagePath $WindowsIso | Out-Null
    }
}

Write-Warn "Next step: boot to fastboot and flash the pipa UEFI image to the Linux boot slot."
