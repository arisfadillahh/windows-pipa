param(
    [string]$WinDrive = "W:",
    [string]$SourceDir = "<WORKSPACE>\scripts"
)

$ErrorActionPreference = "Stop"
$Log = "C:\woa\stage-pipa-usb-pogo-dump-admin.log"
New-Item -ItemType Directory -Force -Path "C:\woa" | Out-Null
Start-Transcript -LiteralPath $Log -Force | Out-Null

try {
    $Root = Join-Path $WinDrive "woa\usb-pogo-dump"
    $SoftHive = Join-Path $WinDrive "Windows\System32\config\SOFTWARE"
    $RunKey = "HKLM\PIPA_SOFT\Microsoft\Windows\CurrentVersion\Run"
    $RunValue = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\woa\usb-pogo-dump\pipa-usb-pogo-dump.ps1"

    if (-not (Test-Path -LiteralPath $SoftHive)) {
        throw "Windows SOFTWARE hive not found at $SoftHive"
    }

    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    Copy-Item -LiteralPath (Join-Path $SourceDir "pipa-usb-pogo-dump.ps1") -Destination (Join-Path $Root "pipa-usb-pogo-dump.ps1") -Force
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
        $cleanupNames = @(
            "PipaI2CDump",
            "PipaI2CResourceDump",
            "PipaKeyboardI2C",
            "PipaKeyboard",
            "PipaQCSPIOnly",
            "PipaPEP8250",
            "PipaUSBPogoDump"
        )
        foreach ($name in $cleanupNames) {
            & reg delete $RunKey /v $name /f | Out-Null
        }

        & reg add $RunKey /v PipaUSBPogoDump /t REG_SZ /d $RunValue /f
        if ($LASTEXITCODE -ne 0) {
            throw "reg add failed: $LASTEXITCODE"
        }
        & reg query $RunKey /v PipaUSBPogoDump
    }
    finally {
        & reg unload HKLM\PIPA_SOFT
    }

    Set-Content -LiteralPath (Join-Path $Root "STAGED.txt") -Value "STAGED $(Get-Date -Format o)" -Encoding ASCII
    Write-Host "USB POGO dump autorun staging complete."
}
finally {
    Stop-Transcript | Out-Null
}

