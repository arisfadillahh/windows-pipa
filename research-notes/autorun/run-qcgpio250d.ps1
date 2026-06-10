$ErrorActionPreference = "Continue"

$Root = "C:\woa\qcgpio250d"
$Driver = Join-Path $Root "driver\qcgpio8250.inf"
$Result = Join-Path $Root "RESULT.txt"
$Done = Join-Path $Root "DONE.txt"
$Transcript = Join-Path $Root "transcript.txt"

New-Item -ItemType Directory -Force -Path $Root | Out-Null
Remove-Item -LiteralPath $Result, $Done, $Transcript -Force -ErrorAction SilentlyContinue

Start-Transcript -Path $Transcript -Force | Out-Null
try {
    "=== PIPA QCGPIO250D TEST START $(Get-Date -Format o) ===" | Tee-Object -FilePath $Result
    "Running elevated as $env:COMPUTERNAME\$env:USERNAME" | Tee-Object -FilePath $Result -Append
    "DriverInf=$Driver" | Tee-Object -FilePath $Result -Append

    "=== before target devices ===" | Tee-Object -FilePath $Result -Append
    pnputil /enum-devices /instanceid "ACPI\QCOM050D\0" /deviceids /properties /resources 2>&1 |
        Tee-Object -FilePath $Result -Append

    "=== install qcgpio8250 ===" | Tee-Object -FilePath $Result -Append
    bcdedit /set testsigning on 2>&1 | Tee-Object -FilePath $Result -Append
    pnputil /add-driver $Driver /install 2>&1 | Tee-Object -FilePath $Result -Append
    "pnputil_exit=$LASTEXITCODE" | Tee-Object -FilePath $Result -Append

    "=== after target devices ===" | Tee-Object -FilePath $Result -Append
    foreach ($id in @("ACPI\QCOM050D\0", "ACPI\QCOM0511\2", "ACPI\QCOM0593\0", "ACPI\QCOM050F\4")) {
        "=== $id ===" | Tee-Object -FilePath $Result -Append
        pnputil /enum-devices /instanceid $id /deviceids /properties /resources 2>&1 |
            Tee-Object -FilePath $Result -Append
    }

    "=== services ===" | Tee-Object -FilePath $Result -Append
    foreach ($svc in @("qcgpio", "qci2c", "qcgpi", "qcpep")) {
        "=== service $svc ===" | Tee-Object -FilePath $Result -Append
        sc.exe query $svc 2>&1 | Tee-Object -FilePath $Result -Append
    }

    "=== driver packages ===" | Tee-Object -FilePath $Result -Append
    pnputil /enum-drivers 2>&1 |
        Select-String -Pattern "qcgpio|qci2c|qcgpi|qcpep|Published Name|Original Name|Provider Name|Driver Version|Class Name" |
        ForEach-Object { $_.Line } |
        Tee-Object -FilePath $Result -Append

    "=== PIPA QCGPIO250D TEST END $(Get-Date -Format o) ===" | Tee-Object -FilePath $Result -Append
    "done $(Get-Date -Format o)" | Set-Content -LiteralPath $Done -Encoding ASCII
}
finally {
    Stop-Transcript | Out-Null
}

