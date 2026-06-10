param(
    [string]$WinDrive = "W:",
    [string]$SourceDir = "<WORKSPACE>\scripts",
    [string]$Qci2cDriverDir = "<PROJECT_ROOT>\kona-drivers\Drivers\SOC\I2C"
)

$ErrorActionPreference = "Stop"
$Log = "C:\woa\stage-pipa-qci2c-offline-admin.log"
New-Item -ItemType Directory -Force -Path "C:\woa" | Out-Null
Start-Transcript -LiteralPath $Log -Force | Out-Null

try {
    $WinRoot = Join-Path $WinDrive "Windows"
    $SoftHive = Join-Path $WinDrive "Windows\System32\config\SOFTWARE"
    $DumpRoot = Join-Path $WinDrive "woa\kbd-i2c-dump"
    $DriverRoot = Join-Path $WinDrive "woa\drivers\qci2c8250"
    $DriverInf = Join-Path $DriverRoot "qci2c8250.inf"
    $RunKey = "HKLM\PIPA_SOFT\Microsoft\Windows\CurrentVersion\Run"
    $RunValue = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\woa\kbd-i2c-dump\pipa-i2c-keyboard-dump.ps1"

    if (-not (Test-Path -LiteralPath $WinRoot)) {
        throw "Windows root not found at $WinRoot"
    }
    if (-not (Test-Path -LiteralPath $SoftHive)) {
        throw "Windows SOFTWARE hive not found at $SoftHive"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $Qci2cDriverDir "qci2c8250.inf"))) {
        throw "qci2c8250.inf not found in $Qci2cDriverDir"
    }

    New-Item -ItemType Directory -Force -Path $DumpRoot, $DriverRoot | Out-Null
    Copy-Item -LiteralPath (Join-Path $SourceDir "pipa-i2c-keyboard-dump.ps1") -Destination (Join-Path $DumpRoot "pipa-i2c-keyboard-dump.ps1") -Force
    Copy-Item -LiteralPath (Join-Path $SourceDir "pipa-i2c-keyboard-dump.cmd") -Destination (Join-Path $DumpRoot "pipa-i2c-keyboard-dump.cmd") -Force
    Copy-Item -Path (Join-Path $Qci2cDriverDir "*") -Destination $DriverRoot -Recurse -Force
    if (-not (Test-Path -LiteralPath $DriverInf)) {
        throw "qci2c driver copy failed; missing $DriverInf"
    }

    Remove-Item -LiteralPath `
        (Join-Path $DumpRoot "RESULT.txt"), `
        (Join-Path $DumpRoot "DONE.txt"), `
        (Join-Path $DumpRoot "pnp-devices.csv"), `
        (Join-Path $DumpRoot "pnp-problems.csv") `
        -Force -ErrorAction SilentlyContinue

    & icacls (Join-Path $WinDrive "woa") /grant "*S-1-1-0:(OI)(CI)F" /T
    if ($LASTEXITCODE -ne 0) {
        throw "icacls failed: $LASTEXITCODE"
    }

    Write-Host "Injecting qci2c driver offline: $DriverInf"
    & dism.exe /Image:$WinDrive\ /Add-Driver /Driver:$DriverInf /ForceUnsigned
    if ($LASTEXITCODE -ne 0) {
        throw "DISM Add-Driver qci2c failed: $LASTEXITCODE"
    }

    & reg load HKLM\PIPA_SOFT $SoftHive
    if ($LASTEXITCODE -ne 0) {
        throw "reg load failed: $LASTEXITCODE"
    }
    try {
        & reg add $RunKey /v PipaI2CDump /t REG_SZ /d $RunValue /f
        if ($LASTEXITCODE -ne 0) {
            throw "reg add failed: $LASTEXITCODE"
        }
        & reg query $RunKey /v PipaI2CDump
    }
    finally {
        & reg unload HKLM\PIPA_SOFT
    }

    Set-Content -LiteralPath (Join-Path $DumpRoot "STAGED-QCI2C.txt") -Value "STAGED QCI2C $(Get-Date -Format o)" -Encoding ASCII
    Write-Host "QCI2C offline injection and dump autorun staging complete."
}
finally {
    Stop-Transcript | Out-Null
}

