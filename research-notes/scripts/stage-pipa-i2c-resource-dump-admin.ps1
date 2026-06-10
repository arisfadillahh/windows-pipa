param(
    [string]$WinDrive = "W:",
    [string]$SourceDir = "<WORKSPACE>\scripts"
)

$ErrorActionPreference = "Stop"
$Log = "C:\woa\stage-pipa-i2c-resource-dump-admin.log"
New-Item -ItemType Directory -Force -Path "C:\woa" | Out-Null
Start-Transcript -LiteralPath $Log -Force | Out-Null

try {
    $Root = Join-Path $WinDrive "woa\i2c-resource-dump"
    $SoftHive = Join-Path $WinDrive "Windows\System32\config\SOFTWARE"
    $RunKey = "HKLM\PIPA_SOFT\Microsoft\Windows\CurrentVersion\Run"
    $RunValue = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\woa\i2c-resource-dump\pipa-i2c-resource-dump.ps1"

    if (-not (Test-Path -LiteralPath $SoftHive)) {
        throw "Windows SOFTWARE hive not found at $SoftHive"
    }

    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    Copy-Item -LiteralPath (Join-Path $SourceDir "pipa-i2c-resource-dump.ps1") -Destination (Join-Path $Root "pipa-i2c-resource-dump.ps1") -Force
    Remove-Item -LiteralPath `
        (Join-Path $Root "RESULT.txt"), `
        (Join-Path $Root "DONE.txt") `
        -Force -ErrorAction SilentlyContinue

    & icacls (Join-Path $WinDrive "woa") /grant "*S-1-1-0:(OI)(CI)F" /T
    if ($LASTEXITCODE -ne 0) {
        throw "icacls failed: $LASTEXITCODE"
    }

    & reg load HKLM\PIPA_SOFT $SoftHive
    if ($LASTEXITCODE -ne 0) {
        throw "reg load failed: $LASTEXITCODE"
    }
    try {
        $oldPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        & reg delete $RunKey /v PipaI2CDump /f 2>$null | Out-Null
        $ErrorActionPreference = $oldPreference
        & reg add $RunKey /v PipaI2CResourceDump /t REG_SZ /d $RunValue /f
        if ($LASTEXITCODE -ne 0) {
            throw "reg add failed: $LASTEXITCODE"
        }
        & reg query $RunKey /v PipaI2CResourceDump
    }
    finally {
        & reg unload HKLM\PIPA_SOFT
    }

    Set-Content -LiteralPath (Join-Path $Root "STAGED.txt") -Value "STAGED $(Get-Date -Format o)" -Encoding ASCII
    Write-Host "I2C resource dump autorun staging complete."
}
finally {
    Stop-Transcript | Out-Null
}

