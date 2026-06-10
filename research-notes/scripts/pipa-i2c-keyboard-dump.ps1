$ErrorActionPreference = "Continue"

$Root = "C:\woa\kbd-i2c-dump"
$Result = Join-Path $Root "RESULT.txt"
$Done = Join-Path $Root "DONE.txt"
$Csv = Join-Path $Root "pnp-devices.csv"
$ProblemCsv = Join-Path $Root "pnp-problems.csv"
$FullPnp = Join-Path $Root "pnputil-full.txt"
$StartupCmd = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\StartUp\Pipa-I2C-Dump.cmd"

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

Add-Line "Pipa v15 I2C/keyboard dump"
Add-Line "Started: $(Get-Date -Format o)"
Add-Line "User: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Add-Line "Computer: $env:COMPUTERNAME"

Run-Capture "BCD current" {
    bcdedit /enum "{current}"
}

Run-Capture "Focused PnP devices" {
    $patterns = "QCOM0511|QCOM2511|QCOM0593|QCOM0519|QCOM050F|QCOM2520|NANO0803|NANOSIC|I2C|GPI"
    Get-PnpDevice | Where-Object {
        ($_.InstanceId -match $patterns) -or ($_.FriendlyName -match $patterns) -or ($_.Class -match "System|HIDClass|Keyboard|Unknown")
    } | Sort-Object InstanceId | Format-Table -AutoSize Status,Class,FriendlyName,InstanceId,Problem
}

Run-Capture "Focused device properties" {
    $ids = Get-PnpDevice | Where-Object {
        $_.InstanceId -match "QCOM0511|QCOM2511|QCOM0593|QCOM0519|QCOM050F|QCOM2520|NANO0803|NANOSIC"
    } | Select-Object -ExpandProperty InstanceId

    foreach ($id in $ids) {
        "---- $id ----"
        Get-PnpDeviceProperty -InstanceId $id -ErrorAction SilentlyContinue |
            Where-Object {
                $_.KeyName -match "DEVPKEY_Device_(HardwareIds|CompatibleIds|ProblemCode|ProblemStatus|Service|Driver|LocationInfo|Parent|Children|Class|ClassGuid)"
            } |
            Select-Object KeyName,Data |
            Format-List
    }
}

Run-Capture "Problem devices" {
    Get-PnpDevice -PresentOnly | Where-Object { $_.Problem -ne 0 -or $_.Status -ne "OK" } |
        Sort-Object Class,FriendlyName |
        Format-Table -AutoSize Status,Class,FriendlyName,InstanceId,Problem
}

Run-Capture "Services" {
    foreach ($svc in "qci2c","qcgpi","qcpep","qcspi","NanosicFilter","HidUsb") {
        "---- sc query $svc ----"
        sc.exe query $svc
    }
}

Run-Capture "Driver packages focused" {
    pnputil /enum-drivers |
        Select-String -Pattern "qci2c|qcpep|qcgpi|qcspi|nanosic|mipad|keyboard" -Context 4,8
}

Run-Capture "PnP util focused windows" {
    pnputil /enum-devices /connected /deviceids /drivers |
        Select-String -Pattern "QCOM0511|QCOM2511|QCOM0593|QCOM0519|QCOM050F|QCOM2520|NANO0803|NANOSIC|qci2c|qcgpi|qcpep|qcspi" -Context 10,14
}

try {
    Get-PnpDevice | Select-Object Status,Class,FriendlyName,InstanceId,Problem | Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath $Csv
    Get-PnpDevice -PresentOnly | Where-Object { $_.Problem -ne 0 -or $_.Status -ne "OK" } |
        Select-Object Status,Class,FriendlyName,InstanceId,Problem |
        Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath $ProblemCsv
    pnputil /enum-devices /connected /deviceids /drivers > $FullPnp
}
catch {
    Add-Line "EXPORT ERROR: $($_.Exception.Message)"
}

Add-Line ""
Add-Line "Completed: $(Get-Date -Format o)"
Set-Content -LiteralPath $Done -Value "DONE $(Get-Date -Format o)" -Encoding ASCII
Remove-Item -LiteralPath $StartupCmd -Force -ErrorAction SilentlyContinue

