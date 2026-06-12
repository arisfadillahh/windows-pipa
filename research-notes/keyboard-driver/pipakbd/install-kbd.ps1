$ErrorActionPreference = "SilentlyContinue"
$log = "C:\woa\install-kbd-log.txt"
$pkg = "C:\woa\pipakbd"
"pipakbd install $(Get-Date -Format o)" | Set-Content -LiteralPath $log -Encoding ASCII

# 1) Trust the driver's test certificate (machine Root + TrustedPublisher) so the
#    test-signed .sys/.cat validate.
certutil -addstore -f Root            "$pkg\pipakbd-testcert.cer" 2>&1 | Add-Content $log
certutil -addstore -f TrustedPublisher "$pkg\pipakbd-testcert.cer" 2>&1 | Add-Content $log

# 2) Allow test-signed kernel drivers to load (persists in this Windows' BCD; needs the
#    reboot in step 4 to take effect if it wasn't already on).
bcdedit /set testsigning on        2>&1 | Add-Content $log
bcdedit /set nointegritychecks on  2>&1 | Add-Content $log

# 3) Install the driver into the store and bind it.
pnputil /add-driver "$pkg\pipakbd.inf" /install 2>&1 | Add-Content $log
pnputil /scan-devices 2>&1 | Add-Content $log
Start-Sleep -Seconds 6

# 4) Report current state.
"== ACPI\NANO0803\0 ==" | Add-Content $log
pnputil /enum-devices /instanceid "ACPI\NANO0803\0" /drivers /properties 2>&1 | Add-Content $log
"== service pipakbd ==" | Add-Content $log
sc.exe query pipakbd 2>&1 | Add-Content $log
"== input/HID devices ==" | Add-Content $log
Get-PnpDevice -Class HIDClass -PresentOnly 2>&1 | Format-Table -AutoSize Status,FriendlyName,InstanceId | Out-String -Width 200 | Add-Content $log

Add-Content $log ""
Add-Content $log "NEXT: restart Windows once (stays on slot B / v31) so testsigning + the driver"
Add-Content $log "bind take full effect, then attach the keyboard cover and test typing."
Start-Process notepad.exe $log
