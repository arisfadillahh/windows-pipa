$ErrorActionPreference = "Continue"

$Root = "C:\woa\usb-pogo-dump"
$Result = Join-Path $Root "RESULT.txt"
$Done = Join-Path $Root "DONE.txt"
$StartupCmd = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\StartUp\Pipa-USB-Pogo-Dump.cmd"

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

$FocusedRegex = "VID_3206|PID_3FFC|Nanosic|HID\\VID|USB\\VID|USB\\ROOT|USB\\VID_2717|VID_258A|QCOM0497|QCOM0498|URS0|USB0|UFN0|QCOM24A5|QCOM0497|QCOM0593|QCOM0519|UCSI|TYPEC|XHCI|USBXHCI|USBHUB|HIDCLASS|Keyboard|Mouse|Touchpad"

Add-Line "Pipa USB POGO / Nanosic keyboard dump"
Add-Line "Started: $(Get-Date -Format o)"
Add-Line "User: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Add-Line "Computer: $env:COMPUTERNAME"

Run-Capture "Focused present PnP devices" {
    Get-PnpDevice -PresentOnly | Where-Object {
        ($_.InstanceId -match $FocusedRegex) -or
        ($_.FriendlyName -match "USB|HID|Nanosic|Keyboard|Mouse|Touchpad|Qualcomm|UCSI|Type-C")
    } | Sort-Object Class,InstanceId | Format-Table -AutoSize Status,Class,FriendlyName,InstanceId,Problem
}

Run-Capture "Focused all PnP devices" {
    Get-PnpDevice | Where-Object {
        ($_.InstanceId -match $FocusedRegex) -or
        ($_.FriendlyName -match "Nanosic|Keyboard|Mouse|Touchpad|QCOM0497|QCOM0498|UCSI|Type-C")
    } | Sort-Object Class,InstanceId | Format-Table -AutoSize Status,Class,FriendlyName,InstanceId,Problem
}

Run-Capture "pnputil connected ids" {
    pnputil /enum-devices /connected /deviceids /services /drivers /properties |
        Select-String -Pattern $FocusedRegex -Context 6,16
}

Run-Capture "pnputil USB class" {
    pnputil /enum-devices /class USB /deviceids /services /drivers /properties |
        Select-String -Pattern "Instance ID|Device Description|Class Name|Class GUID|Manufacturer|Status|Problem|Hardware IDs|Compatible IDs|Service Name|Driver Name|VID_|PID_|ROOT|HUB|XHCI|QCOM|UCSI|Type" -Context 2,10
}

Run-Capture "pnputil HID class" {
    pnputil /enum-devices /class HIDClass /deviceids /services /drivers /properties |
        Select-String -Pattern "Instance ID|Device Description|Class Name|Class GUID|Manufacturer|Status|Problem|Hardware IDs|Compatible IDs|Service Name|Driver Name|VID_|PID_|Nanosic|HID|Keyboard|Mouse|Touchpad" -Context 2,10
}

Run-Capture "pnputil Keyboard class" {
    pnputil /enum-devices /class Keyboard /deviceids /services /drivers /properties |
        Select-String -Pattern "Instance ID|Device Description|Class Name|Status|Problem|Hardware IDs|Compatible IDs|Service Name|Driver Name|VID_|PID_|Nanosic|HID|Keyboard" -Context 2,10
}

Run-Capture "USB controller ACPI resources" {
    foreach ($id in "ACPI\QCOM0497\0","ACPI\QCOM0498\0","ACPI\QCOM0593\0","ACPI\QCOM0519\2&DABA3FF&0","ACPI\QCOM24A5\0") {
        "---- $id ----"
        pnputil /enum-devices /instanceid "$id" /deviceids /relations /services /stack /location /drivers /interfaces /properties /resources
    }
}

Run-Capture "USB and HID services" {
    foreach ($svc in "USBXHCI","USBHUB3","HidUsb","mouhid","kbdhid","NanosicFilter","UcmCxUcsi","UcmUcsiAcpiClient","qcpep","qcgpi") {
        "---- sc query $svc ----"
        sc.exe query $svc
    }
}

Run-Capture "Focused driver packages" {
    pnputil /enum-drivers |
        Select-String -Pattern "Nanosic|HidUsb|keyboard|qcgpi|qcpep|ucsi|usb|xhci|qci2c|qcspi" -Context 4,8
}

Run-Capture "Recent Kernel-PnP USB/HID events" {
    wevtutil qe System /q:"*[System[Provider[@Name='Microsoft-Windows-Kernel-PnP']]]" /rd:true /c:160 /f:text |
        Select-String -Pattern $FocusedRegex -Context 4,10
}

Add-Line ""
Add-Line "Completed: $(Get-Date -Format o)"
Set-Content -LiteralPath $Done -Value "DONE $(Get-Date -Format o)" -Encoding ASCII
Remove-Item -LiteralPath $StartupCmd -Force -ErrorAction SilentlyContinue

