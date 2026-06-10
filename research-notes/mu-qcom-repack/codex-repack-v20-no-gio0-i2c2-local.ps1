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

function To-FvPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return ($Path -replace "\\", "/")
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
$NoSpaceRoot = Join-Path $WoaRoot "muqcom-src"
New-Item -ItemType Directory -Force -Path $WoaRoot | Out-Null
if (Test-Path -LiteralPath $NoSpaceRoot) {
    $existing = Get-Item -LiteralPath $NoSpaceRoot
    if (-not ($existing.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        throw "$NoSpaceRoot exists but is not a junction"
    }
}
else {
    New-Item -ItemType Junction -Path $NoSpaceRoot -Target $Root | Out-Null
}

$SourceRoot = $NoSpaceRoot
$BuildRoot = Join-Path $SourceRoot "Build\pipaPkg\RELEASE_CLANGDWARF"
$FvRoot = Join-Path $BuildRoot "FV"
$ScratchRoot = Join-Path $WoaRoot "mu-repack-v20-no-gio0-i2c2-local"
$FfsAcpiDir = Join-Path $ScratchRoot "Ffs\7E374E25-8E01-4FEE-87F2-390C23C606CDFVMAIN"
$FfsFvDir = Join-Path $ScratchRoot "Ffs\9E21FD93-9C72-4c15-8C4B-E77F1DB2D792FVMAIN_COMPACT"

$Tools = Join-Path $SourceRoot "Mu_Basecore\BaseTools\Bin\Mu-Basetools_extdep\Windows-x86"
$GenSec = Join-Path $Tools "GenSec.exe"
$GenFfs = Join-Path $Tools "GenFfs.exe"
$GenFv = Join-Path $Tools "GenFv.exe"
$Lzma = Join-Path $Tools "LzmaCompress.exe"
$Iasl = Join-Path $ExternalRoot "Robotix22-Mu-Qcom\Silicium-ACPI\Compiler\iasl.exe"
$Mkboot = Join-Path $SourceRoot "ImageResources\mkbootimg.py"

foreach ($required in @($GenSec, $GenFfs, $GenFv, $Lzma, $Iasl, $Mkboot, (Join-Path $FvRoot "FVMAIN.inf"), (Join-Path $FvRoot "FVMAIN_COMPACT.inf"))) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Missing required file: $required"
    }
}

Remove-Item -LiteralPath $ScratchRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $FfsAcpiDir, $FfsFvDir | Out-Null

$I2CAsl = Join-Path $ScratchRoot "I2C2ControllerOnlySSDT.asl"
$I2CAml = Join-Path $ScratchRoot "I2C2ControllerOnlySSDT.aml"

@'
DefinitionBlock ("", "SSDT", 2, "PIPA", "I2C2NOD", 0x00000001)
{
    External (\_SB.PSUB, UnknownObj)

    Scope (\_SB)
    {
        Device (I2C2)
        {
            Name (_HID, "QCOM0511")
            Name (_CID, "QCOM2511")
            Alias (\_SB.PSUB, _SUB)
            Name (_UID, 0x02)
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
        }
    }
}
'@ | Set-Content -LiteralPath $I2CAsl -Encoding ASCII

Push-Location $ScratchRoot
try {
    Run-Tool $Iasl $I2CAsl
}
finally {
    Pop-Location
}
if (-not (Test-Path -LiteralPath $I2CAml)) {
    throw "IASL did not produce $I2CAml"
}

$TouchNoGioAsl = Join-Path $ScratchRoot "TouchMinNoGio0SSDT.asl"
$TouchNoGioAml = Join-Path $ScratchRoot "TouchMinNoGio0SSDT.aml"
$TouchNoGioRaw = Join-Path $FfsAcpiDir "7E374E25-8E01-4FEE-87F2-390C23C606CDSEC5.raw"

@'
DefinitionBlock ("", "SSDT", 2, "PIPA", "TCHNGIO", 0x00000001)
{
    External (\_SB.PSUB, UnknownObj)

    Scope (\_SB)
    {
        Device (PEP0)
        {
            Name (_HID, "QCOM0519")
            Name (_CID, "PNP0D80")

            Method (_SUB, 0, NotSerialized)
            {
                Return (\_SB.PSUB)
            }
        }

        Device (QGP0)
        {
            Name (_HID, "QCOM0593")
            Alias (\_SB.PSUB, _SUB)
            Name (_UID, Zero)
            Name (_CCA, Zero)

            Method (_CRS, 0, Serialized)
            {
                Name (RBUF, ResourceTemplate ()
                {
                    Memory32Fixed (ReadWrite,
                        0x00904000,
                        0x00050000,
                        )
                    Interrupt (ResourceConsumer, Level, ActiveHigh, Exclusive, ,, )
                    {
                        0x00000115,
                    }
                })
                Return (RBUF)
            }
        }

        Device (SPI4)
        {
            Name (_HID, "QCOM050F")
            Name (_CID, "QCOM250F")
            Alias (\_SB.PSUB, _SUB)
            Name (_UID, 0x04)
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
                        0x00990000,
                        0x00004000,
                        )
                    Interrupt (ResourceConsumer, Level, ActiveHigh, Exclusive, ,, )
                    {
                        0x0000025D,
                    }
                })
                Return (RBUF)
            }
        }
    }
}
'@ | Set-Content -LiteralPath $TouchNoGioAsl -Encoding ASCII

Push-Location $ScratchRoot
try {
    Run-Tool $Iasl $TouchNoGioAsl
}
finally {
    Pop-Location
}
if (-not (Test-Path -LiteralPath $TouchNoGioAml)) {
    throw "IASL did not produce $TouchNoGioAml"
}

$SourceAcpiDir = Join-Path $FvRoot "Ffs\7E374E25-8E01-4FEE-87F2-390C23C606CDFVMAIN"
$AcpiGuid = "7E374E25-8E01-4FEE-87F2-390C23C606CD"
$FvGuid = "9E21FD93-9C72-4c15-8C4B-E77F1DB2D792"

$AcpiInputs = @()
Get-ChildItem -LiteralPath $SourceAcpiDir -Filter "${AcpiGuid}SEC*.raw" |
    Sort-Object Name |
    ForEach-Object {
        if ($_.Name -eq "${AcpiGuid}SEC5.raw") {
            Run-Tool $GenSec "-s" "EFI_SECTION_RAW" "-o" $TouchNoGioRaw $TouchNoGioAml
            $dst = $TouchNoGioRaw
        }
        else {
            $dst = Join-Path $FfsAcpiDir $_.Name
            Copy-Item -LiteralPath $_.FullName -Destination $dst
        }
        $script:AcpiInputs += $dst
    }

$I2CRaw = Join-Path $FfsAcpiDir "${AcpiGuid}SEC7.raw"
Run-Tool $GenSec "-s" "EFI_SECTION_RAW" "-o" $I2CRaw $I2CAml
$AcpiInputs += $I2CRaw

$UiSrc = Get-ChildItem -LiteralPath $SourceAcpiDir -Filter "${AcpiGuid}SEC*.ui" | Select-Object -First 1
if (-not $UiSrc) {
    throw "Missing ACPI UI section"
}
$UiDst = Join-Path $FfsAcpiDir $UiSrc.Name
Copy-Item -LiteralPath $UiSrc.FullName -Destination $UiDst
$AcpiInputs += $UiDst

$AcpiFfs = Join-Path $FfsAcpiDir "${AcpiGuid}.ffs"
$GenFfsArgs = @("-t", "EFI_FV_FILETYPE_FREEFORM", "-g", $AcpiGuid, "-o", $AcpiFfs)
foreach ($inputFile in $AcpiInputs) {
    $GenFfsArgs += @("-i", $inputFile)
}
Run-Tool $GenFfs @GenFfsArgs

$RootFvPath = To-FvPath $SourceRoot
$OrigAcpiFfsPath = "$RootFvPath/Build/pipaPkg/RELEASE_CLANGDWARF/FV/Ffs/7E374E25-8E01-4FEE-87F2-390C23C606CDFVMAIN/7E374E25-8E01-4FEE-87F2-390C23C606CD.ffs"
$NewAcpiFfsPath = To-FvPath $AcpiFfs

$FvmainInf = Join-Path $ScratchRoot "FVMAIN-local.inf"
$FvmainText = Get-Content -LiteralPath (Join-Path $FvRoot "FVMAIN.inf") -Raw
$FvmainText = $FvmainText.Replace("/app", $RootFvPath)
$FvmainText = $FvmainText.Replace($OrigAcpiFfsPath, $NewAcpiFfsPath)
$FvmainText | Set-Content -LiteralPath $FvmainInf -Encoding ASCII

$FvmainFv = Join-Path $ScratchRoot "FVMAIN.Fv"
$FvmainMap = Join-Path $ScratchRoot "FVMAIN.Fv.map"
Run-Tool $GenFv "-i" $FvmainInf "-o" $FvmainFv "-m" $FvmainMap

$FvSec = Join-Path $FfsFvDir "${FvGuid}SEC1.1fv.sec"
$GuidedDummy = Join-Path $FfsFvDir "${FvGuid}SEC1.guided.dummy"
$GuidedTmp = Join-Path $FfsFvDir "${FvGuid}SEC1.tmp"
$Guided = Join-Path $FfsFvDir "${FvGuid}SEC1.guided"
$FvFfs = Join-Path $FfsFvDir "${FvGuid}.ffs"

Run-Tool $GenSec "-s" "EFI_SECTION_FIRMWARE_VOLUME_IMAGE" "-o" $FvSec $FvmainFv
Run-Tool $GenSec "--sectionalign" "8" "-o" $GuidedDummy $FvSec
Run-Tool $Lzma "-e" $GuidedDummy "-o" $GuidedTmp
Run-Tool $GenSec "-s" "EFI_SECTION_GUID_DEFINED" "-g" "EE4E5898-3914-4259-9D6E-DC7BD79403CF" "-r" "PROCESSING_REQUIRED" "-o" $Guided $GuidedTmp
Run-Tool $GenFfs "-t" "EFI_FV_FILETYPE_FIRMWARE_VOLUME_IMAGE" "-g" $FvGuid "-o" $FvFfs "-i" $Guided

$OrigFvFfsPath = "$RootFvPath/Build/pipaPkg/RELEASE_CLANGDWARF/FV/Ffs/9E21FD93-9C72-4c15-8C4B-E77F1DB2D792FVMAIN_COMPACT/9E21FD93-9C72-4c15-8C4B-E77F1DB2D792.ffs"
$NewFvFfsPath = To-FvPath $FvFfs

$CompactInf = Join-Path $ScratchRoot "FVMAIN_COMPACT-local.inf"
$CompactText = Get-Content -LiteralPath (Join-Path $FvRoot "FVMAIN_COMPACT.inf") -Raw
$CompactText = $CompactText.Replace("/app", $RootFvPath)
$CompactText = $CompactText.Replace($OrigFvFfsPath, $NewFvFfsPath)
$CompactText | Set-Content -LiteralPath $CompactInf -Encoding ASCII

$Fd = Join-Path $ScratchRoot "PIPA_UEFI-touchmin-v20-no-gio0-i2c2-local.fd"
$FdMap = Join-Path $ScratchRoot "PIPA_UEFI-touchmin-v20-no-gio0-i2c2-local.fd.map"
Run-Tool $GenFv "-i" $CompactInf "-o" $Fd "-m" $FdMap

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
$BootImg = Join-Path $ScratchRoot "Mu-pipa-touchmin-v20-no-gio0-i2c2-local.img"

Join-Bytes -InputFiles @($Bootshim, $Fd) -OutputFile $FdBootshim
Write-Gzip -InputFile $FdBootshim -OutputFile $FdBootshimGz
Join-Bytes -InputFiles @($FdBootshimGz, $Dtb) -OutputFile $BootPayload

$PatchLevel = Get-Date -Format "yyyy-MM"
Run-Tool "python" $Mkboot "--kernel" $BootPayload "--ramdisk" $Ramdisk "--kernel_offset" "0x00000000" "--ramdisk_offset" "0x00000000" "--tags_offset" "0x00000000" "--os_version" "13.0.0" "--os_patch_level" $PatchLevel "--header_version" "1" "-o" $BootImg

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$FinalFd = Join-Path $OutDir "pipa_muold_touchmin_v20-no-gio0-i2c2-local.fd"
$FinalImg = Join-Path $OutDir "pipa_muold_touchmin_v20-no-gio0-i2c2-local.img"
Copy-Item -LiteralPath $Fd -Destination $FinalFd -Force
Copy-Item -LiteralPath $BootImg -Destination $FinalImg -Force

Get-FileHash -Algorithm SHA256 $FinalFd, $FinalImg | Format-Table -AutoSize
Write-Host "DONE"
Write-Host "FD:  $FinalFd"
Write-Host "IMG: $FinalImg"

