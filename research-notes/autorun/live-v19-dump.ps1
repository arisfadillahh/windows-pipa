$ErrorActionPreference = "SilentlyContinue"

$OutDir = "C:\woa\v19-live-dump"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Remove-Item -LiteralPath (Join-Path $OutDir "DONE.txt") -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $OutDir "ERROR.txt") -Force -ErrorAction SilentlyContinue

$Result = Join-Path $OutDir "RESULT.txt"
$Running = Join-Path $OutDir "RUNNING.txt"
"started=$(Get-Date -Format o)" | Set-Content -LiteralPath $Running -Encoding ASCII

function Add-Line {
    param([string]$Text = "")
    $Text | Add-Content -LiteralPath $Result -Encoding UTF8
}

function Run-Cmd {
    param(
        [string]$Title,
        [string]$FilePath,
        [string[]]$Arguments = @()
    )

    Add-Line ""
    Add-Line "==== $Title ===="
    Add-Line "RUN $FilePath $($Arguments -join ' ')"
    try {
        & $FilePath @Arguments 2>&1 | ForEach-Object { Add-Line "$_" }
        Add-Line "exit=$LASTEXITCODE"
    }
    catch {
        Add-Line "ERROR: $($_.Exception.Message)"
    }
}

try {
    "Pipa v19 live PnP dump" | Set-Content -LiteralPath $Result -Encoding UTF8
    Add-Line "started: $(Get-Date -Format o)"
    Add-Line "user: $env:USERDOMAIN\$env:USERNAME"
    Add-Line "image expected: pipa_muold_touchmin_v19-i2c2-hid0511-uid2-nodep-local"
    Add-Line "no driver install is performed by this script"

    Add-Line ""
    Add-Line "==== Get-PnpDevice summary ===="
    Get-PnpDevice -PresentOnly |
        Where-Object {
            $_.InstanceId -match "QCOM0511|QCOM2511|QCOM050D|QCOM0593|QCOM0519|QCOM050F|NANO|I2C|GPI|GPIO"
        } |
        Sort-Object InstanceId |
        Format-Table -AutoSize Status,Class,FriendlyName,InstanceId,Problem |
        Out-String -Width 240 |
        ForEach-Object { Add-Line $_ }

    foreach ($id in @(
        "ACPI\QCOM2511\2",
        "ACPI\QCOM0511\2",
        "ACPI\QCOM050D\0",
        "ACPI\QCOM0593\0",
        "ACPI\QCOM0519\2&DABA3FF&0",
        "ACPI\QCOM050F\4"
    )) {
        Run-Cmd "pnputil full $id" "pnputil.exe" @("/enum-devices", "/instanceid", $id, "/deviceids", "/drivers", "/properties", "/resources")
    }

    foreach ($svc in @("qci2c", "qcgpio", "qcgpi", "qcpep", "qcspi")) {
        Run-Cmd "sc query $svc" "sc.exe" @("query", $svc)
    }

    "completed=$(Get-Date -Format o)" | Set-Content -LiteralPath (Join-Path $OutDir "DONE.txt") -Encoding ASCII
}
catch {
    "error=$($_.Exception.Message)" | Set-Content -LiteralPath (Join-Path $OutDir "ERROR.txt") -Encoding ASCII
}
finally {
    Remove-Item -LiteralPath $Running -Force -ErrorAction SilentlyContinue
}

