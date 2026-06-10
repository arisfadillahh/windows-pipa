$ErrorActionPreference = "Continue"

$OutDir = "C:\woa\v19-baseline-dump"
$Result = Join-Path $OutDir "RESULT.txt"
$Done = Join-Path $OutDir "DONE.txt"
$Transcript = Join-Path $OutDir "transcript.txt"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Remove-Item -LiteralPath $Done -Force -ErrorAction SilentlyContinue
Set-Content -LiteralPath $Result -Value "=== PIPA V19 BASELINE DUMP START $(Get-Date -Format o) ===" -Encoding UTF8
Start-Transcript -LiteralPath $Transcript -Force | Out-Null

function Add-Line {
    param([string]$Text = "")
    $Text | Tee-Object -FilePath $Result -Append
}

function Run-Cmd {
    param([string]$Title, [string]$File, [string[]]$CmdArgs)
    Add-Line ""
    Add-Line "=== $Title ==="
    Add-Line "RUN: $File $($CmdArgs -join ' ')"
    $out = & $File @CmdArgs 2>&1
    $code = $LASTEXITCODE
    if ($out) {
        $out | Tee-Object -FilePath $Result -Append
    }
    Add-Line "EXIT: $code"
}

function Dump-Pnp {
    param([string]$InstanceId)
    Run-Cmd "PNP $InstanceId full" "pnputil.exe" @(
        "/enum-devices", "/instanceid", $InstanceId, "/resources", "/properties", "/deviceids", "/drivers"
    )
}

try {
    Add-Line "Running as: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
    Add-Line "Computer: $env:COMPUTERNAME"
    Add-Line "Expected image: v19-i2c2-hid0511-uid2-nodep-local"

    foreach ($id in @(
        "ACPI\QCOM050D\0",
        "ACPI\QCOM0511\2",
        "ACPI\QCOM2511\2",
        "ACPI\QCOM0593\0",
        "ACPI\QCOM050F\4",
        "ACPI\QCOM0519\2&DABA3FF&0",
        "ACPI\QCOM2519\2&DABA3FF&0"
    )) {
        Dump-Pnp $id
    }

    Run-Cmd "Problem devices resources" "pnputil.exe" @("/enum-devices", "/problem", "/resources", "/deviceids", "/drivers")
    Run-Cmd "System class resources" "pnputil.exe" @("/enum-devices", "/class", "System", "/resources", "/deviceids", "/drivers")
    Run-Cmd "HID class devices" "pnputil.exe" @("/enum-devices", "/class", "HIDClass", "/deviceids", "/drivers")
    Run-Cmd "Keyboard class devices" "pnputil.exe" @("/enum-devices", "/class", "Keyboard", "/deviceids", "/drivers")

    foreach ($svc in @("qcgpio", "qci2c", "qcgpi", "qcpep", "qcspi")) {
        Run-Cmd "service $svc" "sc.exe" @("query", $svc)
    }

    Add-Line ""
    Add-Line "=== PowerShell target devices ==="
    foreach ($id in @(
        "ACPI\QCOM050D\0",
        "ACPI\QCOM0511\2",
        "ACPI\QCOM2511\2",
        "ACPI\QCOM0593\0",
        "ACPI\QCOM050F\4"
    )) {
        Add-Line ""
        Add-Line "--- $id ---"
        Get-PnpDevice -InstanceId $id -ErrorAction Continue |
            Format-List * |
            Out-String -Width 260 |
            Tee-Object -FilePath $Result -Append

        Get-PnpDeviceProperty -InstanceId $id -ErrorAction Continue |
            Sort-Object KeyName |
            Format-Table KeyName,Type,Data -Wrap -AutoSize |
            Out-String -Width 260 |
            Tee-Object -FilePath $Result -Append
    }

    Set-Content -LiteralPath $Done -Value "DONE $(Get-Date -Format o)" -Encoding ASCII
}
catch {
    Add-Line "FAILED: $($_.Exception.Message)"
}
finally {
    Add-Line ""
    Add-Line "=== PIPA V19 BASELINE DUMP END $(Get-Date -Format o) ==="
    & reg.exe delete "HKLM\Software\Microsoft\Windows\CurrentVersion\Run" /v PipaV19Dump /f 2>&1 | Out-Null
    Stop-Transcript | Out-Null
}

