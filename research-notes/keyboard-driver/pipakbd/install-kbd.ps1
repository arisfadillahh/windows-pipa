$ErrorActionPreference = "SilentlyContinue"
$log = "C:\woa\install-kbd-log.txt"
$pkg = "C:\woa\pipakbd"
"pipakbd install v2 $(Get-Date -Format o)" | Set-Content -LiteralPath $log -Encoding ASCII

# 0) Remove any previously-installed pipakbd package so the new one (with the I2C enable
#    sequence) binds cleanly.
$drivers = pnputil /enum-drivers
$cur = $null
foreach ($line in $drivers) {
    if ($line -match 'Published Name\s*:\s*(oem\d+\.inf)') { $cur = $Matches[1] }
    if ($line -match 'Original Name\s*:\s*pipakbd\.inf' -and $cur) {
        "removing stale $cur" | Add-Content $log
        pnputil /delete-driver $cur /uninstall /force 2>&1 | Add-Content $log
        $cur = $null
    }
}

# 1) Trust the (current build's) test certificate.
certutil -addstore -f Root            "$pkg\pipakbd-testcert.cer" 2>&1 | Add-Content $log
certutil -addstore -f TrustedPublisher "$pkg\pipakbd-testcert.cer" 2>&1 | Add-Content $log

# 2) Allow test-signed kernel drivers (persists; needs the reboot in step 4).
bcdedit /set testsigning on        2>&1 | Add-Content $log
bcdedit /set nointegritychecks on  2>&1 | Add-Content $log

# 3) Install + bind.
pnputil /add-driver "$pkg\pipakbd.inf" /install 2>&1 | Add-Content $log
pnputil /scan-devices 2>&1 | Add-Content $log
Start-Sleep -Seconds 6

# 4) Report.
"== ACPI\NANO0803\0 ==" | Add-Content $log
pnputil /enum-devices /instanceid "ACPI\NANO0803\0" /stack /drivers /properties 2>&1 | Add-Content $log
"== service pipakbd ==" | Add-Content $log
sc.exe query pipakbd 2>&1 | Add-Content $log
"== USB/HID input devices ==" | Add-Content $log
Get-PnpDevice -PresentOnly 2>&1 | Where-Object { $_.InstanceId -match 'VID_258A|NANO0803|HID' } | Format-Table -AutoSize Status,FriendlyName,InstanceId | Out-String -Width 220 | Add-Content $log

Add-Content $log ""
Add-Content $log "NEXT: restart Windows once, then attach the keyboard and type."
Start-Process notepad.exe $log
