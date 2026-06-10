$ErrorActionPreference = "Continue"

$Root = "C:\woa\i2c-resource-dump"
$Result = Join-Path $Root "RESULT.txt"
$Done = Join-Path $Root "DONE.txt"
$StartupCmd = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\StartUp\Pipa-I2C-Resource-Dump.cmd"

New-Item -ItemType Directory -Force -Path $Root | Out-Null
Remove-Item -LiteralPath $Result, $Done -Force -ErrorAction SilentlyContinue

function Add-Line {
    param([string]$Text = "")
    Add-Content -LiteralPath $Result -Value $Text -Encoding UTF8
}

function Add-Section {
    param([string]$Title)
    Add-Line ""
    Add-Line "==== $Title ===="
}

function Run-Capture {
    param(
        [string]$Title,
        [scriptblock]$Block
    )
    Add-Section $Title
    try {
        & $Block 2>&1 | Out-String -Width 4096 | Add-Content -LiteralPath $Result -Encoding UTF8
    }
    catch {
        Add-Line "ERROR: $($_.Exception.Message)"
    }
}

$Targets = @(
    "ACPI\QCOM0511\2",
    "ACPI\QCOM0593\0",
    "ACPI\QCOM0519\2&DABA3FF&0",
    "ACPI\QCOM050F\4",
    "ACPI\QCOM050D\0",
    "ACPI\QCOM2519\2&DABA3FF&0"
)

Add-Line "Pipa I2C resource arbitration dump"
Add-Line "Started: $(Get-Date -Format o)"
Add-Line "User: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Add-Line "Computer: $env:COMPUTERNAME"

Run-Capture "Focused PnP summary" {
    Get-PnpDevice | Where-Object {
        $_.InstanceId -match "QCOM0511|QCOM2511|QCOM0593|QCOM0519|QCOM050F|QCOM050D|NANO0803|NANOSIC|I2C|GPI"
    } | Sort-Object InstanceId | Format-Table -AutoSize Status,Class,FriendlyName,InstanceId,Problem
}

foreach ($id in $Targets) {
    Run-Capture "pnputil full $id" {
        pnputil /enum-devices /instanceid "$id" /deviceids /relations /services /stack /location /drivers /interfaces /properties /resources
    }
}

Run-Capture "Problem devices with resources" {
    pnputil /enum-devices /problem /deviceids /drivers /properties /resources
}

Run-Capture "All QCOM system devices with resources" {
    pnputil /enum-devices /class System /deviceids /drivers /properties /resources |
        Select-String -Pattern "QCOM0511|QCOM2511|QCOM0593|QCOM0519|QCOM050F|QCOM050D|QCOM2519|I2C|GPI|Memory|Interrupt|Problem|Status|Instance ID|Device Description|Driver Name" -Context 4,10
}

Run-Capture "Get-PnpDeviceProperty all focused" {
    foreach ($id in $Targets) {
        "---- $id ----"
        Get-PnpDeviceProperty -InstanceId $id -ErrorAction SilentlyContinue |
            Sort-Object KeyName |
            Format-Table -AutoSize KeyName,Type,Data
    }
}

Run-Capture "Kernel PnP recent events" {
    wevtutil qe System /q:"*[System[Provider[@Name='Microsoft-Windows-Kernel-PnP']]]" /rd:true /c:120 /f:text
}

Run-Capture "Services" {
    foreach ($svc in "qci2c","qcgpi","qcpep","qcspi","SpbCx","NanosicFilter","HidUsb") {
        "---- sc query $svc ----"
        sc.exe query $svc
    }
}

Run-Capture "Driver packages focused" {
    pnputil /enum-drivers |
        Select-String -Pattern "qci2c|qcpep|qcgpi|qcspi|nanosic|mipad|keyboard" -Context 4,8
}

Add-Line ""
Add-Line "Completed: $(Get-Date -Format o)"
Set-Content -LiteralPath $Done -Value "DONE $(Get-Date -Format o)" -Encoding ASCII
Remove-Item -LiteralPath $StartupCmd -Force -ErrorAction SilentlyContinue

