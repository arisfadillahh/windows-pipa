$ErrorActionPreference = "SilentlyContinue"
$log = "C:\woa\fix-spi-log.txt"
"start $(Get-Date -Format o)" | Set-Content -LiteralPath $log -Encoding ASCII

# 1) Arm boot telemetry so even a BSOD/dead-display boot self-reports next time.
"== arm boot telemetry ==" | Add-Content -LiteralPath $log
schtasks /create /tn "PipaBootTelemetry" /sc onstart /ru SYSTEM /rl HIGHEST /tr "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\woa\boottest\boot-telemetry.ps1" /f 2>&1 |
    ForEach-Object { "$_" } | Add-Content -LiteralPath $log

# 2) Pre-state of SPI4.
"== before SPI4 ==" | Add-Content -LiteralPath $log
pnputil.exe /enum-devices /instanceid "ACPI\QCOM050F\4" /drivers 2>&1 | ForEach-Object { "$_" } | Add-Content -LiteralPath $log

# 3) Install qcspi8250 (DEMAND_START; SPI4 _DEP removed in v29 so the old 0xA0 PEP path is gone).
"== add-driver qcspi8250 ==" | Add-Content -LiteralPath $log
pnputil.exe /add-driver C:\woa\qcspi-only\driver\qcspi8250.inf /install 2>&1 | ForEach-Object { "$_" } | Add-Content -LiteralPath $log
"pnputil_exit=$LASTEXITCODE" | Add-Content -LiteralPath $log

"== scan-devices ==" | Add-Content -LiteralPath $log
pnputil.exe /scan-devices 2>&1 | ForEach-Object { "$_" } | Add-Content -LiteralPath $log
Start-Sleep -Seconds 8

"== after SPI4 ==" | Add-Content -LiteralPath $log
pnputil.exe /enum-devices /instanceid "ACPI\QCOM050F\4" /drivers /properties 2>&1 | ForEach-Object { "$_" } | Add-Content -LiteralPath $log
"== sc query qcspi ==" | Add-Content -LiteralPath $log
sc.exe query qcspi 2>&1 | ForEach-Object { "$_" } | Add-Content -LiteralPath $log
"done $(Get-Date -Format o)" | Add-Content -LiteralPath $log

# 4) full dump + open it
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\woa\v19-live-dump\live-v19-dump.ps1"
Start-Process notepad.exe "C:\woa\v19-live-dump\RESULT.txt"
