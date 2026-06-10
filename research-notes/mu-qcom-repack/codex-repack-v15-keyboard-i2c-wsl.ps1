param(
    [string]$OutDir = "<ARTIFACT_DIR>"
)

$ErrorActionPreference = "Stop"

function Run-Tool {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments
    )

    Write-Host "RUN $FilePath $($Arguments -join ' ')"
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed ($LASTEXITCODE): $FilePath $($Arguments -join ' ')"
    }
}

function To-WslPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $drive = $full.Substring(0, 1).ToLowerInvariant()
    $rest = $full.Substring(2).Replace("\", "/")
    return "/mnt/host/$drive$rest"
}

function To-DockerWoaPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $prefix = [System.IO.Path]::GetFullPath("C:\woa")
    if (-not $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is not under C:\woa: $Path"
    }
    $rest = $full.Substring($prefix.Length).TrimStart("\").Replace("\", "/")
    if ([string]::IsNullOrWhiteSpace($rest)) {
        return "/woa"
    }
    return "/woa/$rest"
}

function To-FvPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (To-WslPath $Path)
}

function Join-Bytes {
    param(
        [Parameter(Mandatory = $true)][string[]]$InputFiles,
        [Parameter(Mandatory = $true)][string]$OutputFile
    )

    $outStream = [System.IO.File]::Create($OutputFile)
    try {
        foreach ($file in $InputFiles) {
            $inStream = [System.IO.File]::OpenRead($file)
            try {
                $inStream.CopyTo($outStream)
            }
            finally {
                $inStream.Dispose()
            }
        }
    }
    finally {
        $outStream.Dispose()
    }
}

function Write-Gzip {
    param(
        [Parameter(Mandatory = $true)][string]$InputFile,
        [Parameter(Mandatory = $true)][string]$OutputFile
    )

    $source = [System.IO.File]::OpenRead($InputFile)
    try {
        $dest = [System.IO.File]::Create($OutputFile)
        try {
            $gzip = [System.IO.Compression.GzipStream]::new($dest, [System.IO.Compression.CompressionLevel]::Optimal)
            try {
                $source.CopyTo($gzip)
            }
            finally {
                $gzip.Dispose()
            }
        }
        finally {
            $dest.Dispose()
        }
    }
    finally {
        $source.Dispose()
    }
}

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExternalRoot = Split-Path -Parent $Root
$WoaRoot = "C:\woa"
$SourceRoot = Join-Path $WoaRoot "muqcom-src"
$ScratchRoot = Join-Path $WoaRoot "mu-repack-v15-keyboard-i2c-wsl"
$FfsAcpiDir = Join-Path $ScratchRoot "Ffs\7E374E25-8E01-4FEE-87F2-390C23C606CDFVMAIN"
$FfsFvDir = Join-Path $ScratchRoot "Ffs\9E21FD93-9C72-4c15-8C4B-E77F1DB2D792FVMAIN_COMPACT"

New-Item -ItemType Directory -Force -Path $WoaRoot | Out-Null
if (Test-Path -LiteralPath $SourceRoot) {
    $existing = Get-Item -LiteralPath $SourceRoot
    if (-not ($existing.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        throw "$SourceRoot exists but is not a junction"
    }
}
else {
    New-Item -ItemType Junction -Path $SourceRoot -Target $Root | Out-Null
}

$BuildRoot = Join-Path $SourceRoot "Build\pipaPkg\RELEASE_CLANGDWARF"
$FvRoot = Join-Path $BuildRoot "FV"
$Iasl = Join-Path $ExternalRoot "Robotix22-Mu-Qcom\Silicium-ACPI\Compiler\iasl.exe"
$Mkboot = Join-Path $SourceRoot "ImageResources\mkbootimg.py"

foreach ($required in @($Iasl, $Mkboot, (Join-Path $FvRoot "FVMAIN.inf"), (Join-Path $FvRoot "FVMAIN_COMPACT.inf"))) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Missing required file: $required"
    }
}

Remove-Item -LiteralPath $ScratchRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $FfsAcpiDir, $FfsFvDir | Out-Null

$KeyboardAsl = Join-Path $ScratchRoot "KeyboardI2CMinSSDT.asl"
$KeyboardAml = Join-Path $ScratchRoot "KeyboardI2CMinSSDT.aml"

@'
DefinitionBlock ("", "SSDT", 2, "PIPA", "KBDI2C", 0x00000001)
{
    External (\_SB.PSUB, UnknownObj)
    External (\_SB.PEP0, DeviceObj)
    External (\_SB.QGP0, DeviceObj)
    External (\_SB.GIO0, DeviceObj)

    Scope (\_SB)
    {
        Device (I2C2)
        {
            Name (_HID, "QCOM0511")
            Name (_CID, "QCOM2511")
            Alias (\_SB.PSUB, _SUB)
            Name (_UID, 0x02)
            Name (_DEP, Package (0x02)
            {
                PEP0,
                QGP0
            })
            Name (_CCA, Zero)

            Method (_CRS, 0, NotSerialized)
            {
                Name (RBUF, ResourceTemplate ()
                {
                    Memory32Fixed (ReadWrite,
                        0x00988000,
                        0x00004000,
                        )
                    Interrupt (ResourceConsumer, Level, ActiveHigh, Exclusive, ,, )
                    {
                        0x0000025B,
                    }
                })
                Return (RBUF)
            }

            Device (XMKB)
            {
                Name (_HID, "NANO0803")
                Name (_UID, Zero)
                Name (_DDN, "Nanosic 803 Keyboard MCU")
                Name (_S0W, 0x03)

                Method (_STA, 0, NotSerialized)
                {
                    Return (0x0F)
                }

                Method (_CRS, 0, Serialized)
                {
                    Name (RBUF, ResourceTemplate ()
                    {
                        I2cSerialBusV2 (0x004C, ControllerInitiated, 0x00061A80,
                            AddressingMode7Bit, "\\_SB.I2C2", 0x00,
                            ResourceConsumer,,,)

                        GpioInt (Level, ActiveLow, ExclusiveAndWake, PullUp, 0x0000,
                            "\\_SB.GIO0", 0x00, ResourceConsumer,,) { 100 }

                        GpioIo (Exclusive, PullNone, 0x0000, 0x0000, IoRestrictionOutputOnly,
                            "\\_SB.GIO0", 0x00, ResourceConsumer,,) { 141, 46, 127, 155 }
                    })
                    Return (RBUF)
                }
            }
        }
    }
}
'@ | Set-Content -LiteralPath $KeyboardAsl -Encoding ASCII

Push-Location $ScratchRoot
try {
    Run-Tool $Iasl $KeyboardAsl
}
finally {
    Pop-Location
}
if (-not (Test-Path -LiteralPath $KeyboardAml)) {
    throw "IASL did not produce $KeyboardAml"
}

$SourceAcpiDir = Join-Path $FvRoot "Ffs\7E374E25-8E01-4FEE-87F2-390C23C606CDFVMAIN"
$AcpiGuid = "7E374E25-8E01-4FEE-87F2-390C23C606CD"
$FvGuid = "9E21FD93-9C72-4c15-8C4B-E77F1DB2D792"

$AcpiInputs = @()
foreach ($name in @(
    "${AcpiGuid}SEC1.raw",
    "${AcpiGuid}SEC2.raw",
    "${AcpiGuid}SEC3.raw",
    "${AcpiGuid}SEC4.raw",
    "${AcpiGuid}SEC5.raw"
)) {
    $src = Join-Path $SourceAcpiDir $name
    $dst = Join-Path $FfsAcpiDir $name
    Copy-Item -LiteralPath $src -Destination $dst
    $AcpiInputs += $dst
}

$UiDst = Join-Path $FfsAcpiDir "${AcpiGuid}SEC6.ui"
Copy-Item -LiteralPath (Join-Path $SourceAcpiDir "${AcpiGuid}SEC6.ui") -Destination $UiDst

$RootFvPath = "/src"
$OrigAcpiFfsPath = "$RootFvPath/Build/pipaPkg/RELEASE_CLANGDWARF/FV/Ffs/7E374E25-8E01-4FEE-87F2-390C23C606CDFVMAIN/7E374E25-8E01-4FEE-87F2-390C23C606CD.ffs"
$NewAcpiFfsPath = To-DockerWoaPath (Join-Path $FfsAcpiDir "${AcpiGuid}.ffs")

$FvmainInf = Join-Path $ScratchRoot "FVMAIN-local.inf"
$FvmainText = Get-Content -LiteralPath (Join-Path $FvRoot "FVMAIN.inf") -Raw
$FvmainText = $FvmainText.Replace("/app", $RootFvPath)
$FvmainText = $FvmainText.Replace($OrigAcpiFfsPath, $NewAcpiFfsPath)
[System.IO.File]::WriteAllText($FvmainInf, $FvmainText, [System.Text.Encoding]::ASCII)

$OrigFvFfsPath = "$RootFvPath/Build/pipaPkg/RELEASE_CLANGDWARF/FV/Ffs/9E21FD93-9C72-4c15-8C4B-E77F1DB2D792FVMAIN_COMPACT/9E21FD93-9C72-4c15-8C4B-E77F1DB2D792.ffs"
$NewFvFfsPath = To-DockerWoaPath (Join-Path $FfsFvDir "${FvGuid}.ffs")

$CompactInf = Join-Path $ScratchRoot "FVMAIN_COMPACT-local.inf"
$CompactText = Get-Content -LiteralPath (Join-Path $FvRoot "FVMAIN_COMPACT.inf") -Raw
$CompactText = $CompactText.Replace("/app", $RootFvPath)
$CompactText = $CompactText.Replace($OrigFvFfsPath, $NewFvFfsPath)
[System.IO.File]::WriteAllText($CompactInf, $CompactText, [System.Text.Encoding]::ASCII)

$ScratchWsl = To-DockerWoaPath $ScratchRoot
$ToolsWsl = "$RootFvPath/Mu_Basecore/BaseTools/Bin/Mu-Basetools_extdep/Linux-x86"
$KeyboardAmlWsl = To-DockerWoaPath $KeyboardAml
$UiWsl = To-DockerWoaPath $UiDst
$AcpiArgs = ""
foreach ($input in $AcpiInputs) {
    $AcpiArgs += " -i `"`"$(To-DockerWoaPath $input)`"`""
}

$RepackSh = Join-Path $ScratchRoot "repack.sh"
$bash = @"
#!/bin/sh
set -eu
TOOLS="$ToolsWsl"
SCRATCH="$ScratchWsl"
ACPI_GUID="$AcpiGuid"
FV_GUID="$FvGuid"
ACPI_DIR="$ScratchWsl/Ffs/7E374E25-8E01-4FEE-87F2-390C23C606CDFVMAIN"
FV_DIR="$ScratchWsl/Ffs/9E21FD93-9C72-4c15-8C4B-E77F1DB2D792FVMAIN_COMPACT"
chmod +x "`$TOOLS/GenSec" "`$TOOLS/GenFfs" "`$TOOLS/GenFv" "`$TOOLS/LzmaCompress"
"`$TOOLS/GenSec" -s EFI_SECTION_RAW -o "`$ACPI_DIR/`${ACPI_GUID}SEC7.raw" "$KeyboardAmlWsl"
"`$TOOLS/GenFfs" -t EFI_FV_FILETYPE_FREEFORM -g "`$ACPI_GUID" -o "`$ACPI_DIR/`${ACPI_GUID}.ffs"$AcpiArgs -i "`$ACPI_DIR/`${ACPI_GUID}SEC7.raw" -i "$UiWsl"
"`$TOOLS/GenFv" -i "$ScratchWsl/FVMAIN-local.inf" -o "$ScratchWsl/FVMAIN.Fv" -m "$ScratchWsl/FVMAIN.Fv.map"
"`$TOOLS/GenSec" -s EFI_SECTION_FIRMWARE_VOLUME_IMAGE -o "`$FV_DIR/`${FV_GUID}SEC1.1fv.sec" "$ScratchWsl/FVMAIN.Fv"
"`$TOOLS/GenSec" --sectionalign 8 -o "`$FV_DIR/`${FV_GUID}SEC1.guided.dummy" "`$FV_DIR/`${FV_GUID}SEC1.1fv.sec"
"`$TOOLS/LzmaCompress" -e "`$FV_DIR/`${FV_GUID}SEC1.guided.dummy" -o "`$FV_DIR/`${FV_GUID}SEC1.tmp"
"`$TOOLS/GenSec" -s EFI_SECTION_GUID_DEFINED -g EE4E5898-3914-4259-9D6E-DC7BD79403CF -r PROCESSING_REQUIRED -o "`$FV_DIR/`${FV_GUID}SEC1.guided" "`$FV_DIR/`${FV_GUID}SEC1.tmp"
"`$TOOLS/GenFfs" -t EFI_FV_FILETYPE_FIRMWARE_VOLUME_IMAGE -g "`$FV_GUID" -o "`$FV_DIR/`${FV_GUID}.ffs" -i "`$FV_DIR/`${FV_GUID}SEC1.guided"
"`$TOOLS/GenFv" -i "$ScratchWsl/FVMAIN_COMPACT-local.inf" -o "$ScratchWsl/PIPA_UEFI-touchmin-v15-keyboard-i2c-wsl.fd" -m "$ScratchWsl/PIPA_UEFI-touchmin-v15-keyboard-i2c-wsl.fd.map"
"@
[System.IO.File]::WriteAllText($RepackSh, $bash.Replace("`r`n", "`n"), [System.Text.UTF8Encoding]::new($false))

$RepackShWsl = To-DockerWoaPath $RepackSh
$RootDocker = (Resolve-Path -LiteralPath $Root).Path.Replace("\", "/")
Run-Tool "docker" "run" "--rm" "-v" "${RootDocker}:/src" "-v" "C:/woa:/woa" "debian:bookworm-slim" "sh" $RepackShWsl

$Fd = Join-Path $ScratchRoot "PIPA_UEFI-touchmin-v15-keyboard-i2c-wsl.fd"
$fdInfo = Get-Item -LiteralPath $Fd
if ($fdInfo.Length -ne 3145728) {
    throw "Unexpected FD size: $($fdInfo.Length)"
}

$Bootshim = Join-Path $SourceRoot "BootShim\BootShim.bin"
$Dtb = Join-Path $SourceRoot "ImageResources\DTBs\pipa.dtb"
$Ramdisk = Join-Path $SourceRoot "ImageResources\ramdisk"
$FdBootshim = Join-Path $ScratchRoot "PIPA_UEFI.fd-bootshim"
$FdBootshimGz = Join-Path $ScratchRoot "PIPA_UEFI.fd-bootshim.gz"
$BootPayload = Join-Path $ScratchRoot "bootpayload.bin"
$BootImg = Join-Path $ScratchRoot "Mu-pipa-touchmin-v15-keyboard-i2c-wsl.img"

Join-Bytes -InputFiles @($Bootshim, $Fd) -OutputFile $FdBootshim
Write-Gzip -InputFile $FdBootshim -OutputFile $FdBootshimGz
Join-Bytes -InputFiles @($FdBootshimGz, $Dtb) -OutputFile $BootPayload

$PatchLevel = Get-Date -Format "yyyy-MM"
Run-Tool "python" $Mkboot "--kernel" $BootPayload "--ramdisk" $Ramdisk "--kernel_offset" "0x00000000" "--ramdisk_offset" "0x00000000" "--tags_offset" "0x00000000" "--os_version" "13.0.0" "--os_patch_level" $PatchLevel "--header_version" "1" "-o" $BootImg

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$FinalFd = Join-Path $OutDir "pipa_muold_touchmin_v15-keyboard-i2c-wsl.fd"
$FinalImg = Join-Path $OutDir "pipa_muold_touchmin_v15-keyboard-i2c-wsl.img"
Copy-Item -LiteralPath $Fd -Destination $FinalFd -Force
Copy-Item -LiteralPath $BootImg -Destination $FinalImg -Force

Get-FileHash -Algorithm SHA256 $FinalFd, $FinalImg | Format-Table -AutoSize
Write-Host "DONE"
Write-Host "FD:  $FinalFd"
Write-Host "IMG: $FinalImg"

