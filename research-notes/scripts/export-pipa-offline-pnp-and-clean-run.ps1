param(
    [string]$WinDrive = "W:",
    [string]$OutDir = "C:\woa\pipa-offline-pnp-export"
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$Log = Join-Path $OutDir "export.log"
$StatusLog = Join-Path $OutDir "status.log"
Start-Transcript -LiteralPath $Log -Force | Out-Null

try {
    $SystemHive = Join-Path $WinDrive "Windows\System32\Config\SYSTEM"
    $SoftwareHive = Join-Path $WinDrive "Windows\System32\Config\SOFTWARE"
    $sysLoaded = $false
    $softLoaded = $false

    & reg load HKLM\PIPA_SYS $SystemHive
    if ($LASTEXITCODE -ne 0) { throw "reg load SYSTEM failed: $LASTEXITCODE" }
    $sysLoaded = $true

    foreach ($key in @("QCOM0511", "QCOM0593", "QCOM0519", "QCOM050F", "QCOM050D", "QCOM2519")) {
        $target = "HKLM\PIPA_SYS\ControlSet001\Enum\ACPI\$key"
        $out = Join-Path $OutDir "$key.regquery.txt"
        & reg query $target /s > $out 2>&1
        "reg query $target exit=$LASTEXITCODE" | Add-Content -LiteralPath $StatusLog
    }

    foreach ($key in @("Services\qci2c", "Services\qcgpi", "Services\qcpep", "Services\qcspi")) {
        $target = "HKLM\PIPA_SYS\ControlSet001\$key"
        $name = ($key -replace "\\", "-")
        $out = Join-Path $OutDir "$name.regquery.txt"
        & reg query $target /s > $out 2>&1
        "reg query $target exit=$LASTEXITCODE" | Add-Content -LiteralPath $StatusLog
    }

    & reg load HKLM\PIPA_SOFT $SoftwareHive
    if ($LASTEXITCODE -ne 0) { throw "reg load SOFTWARE failed: $LASTEXITCODE" }
    $softLoaded = $true

    $runKey = "HKLM\PIPA_SOFT\Microsoft\Windows\CurrentVersion\Run"
    & reg query $runKey > (Join-Path $OutDir "Run-before.txt") 2>&1
    & reg delete $runKey /v PipaI2CDump /f > (Join-Path $OutDir "Run-delete.txt") 2>&1
    & reg query $runKey > (Join-Path $OutDir "Run-after.txt") 2>&1
}
finally {
    if ($softLoaded) { & reg unload HKLM\PIPA_SOFT | Out-Null }
    if ($sysLoaded) { & reg unload HKLM\PIPA_SYS | Out-Null }
    Stop-Transcript | Out-Null
}

