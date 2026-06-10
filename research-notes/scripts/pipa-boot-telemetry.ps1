# Pipa boot telemetry — runs at boot as SYSTEM (ONSTART scheduled task).
# Captures display/GPU/GPIO/I2C state so a DEAD-DISPLAY boot still self-reports to disk.
$ErrorActionPreference = "SilentlyContinue"
$OutDir = "C:\woa\boottest"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# stamp file name by boot time so each boot keeps its own report
$stamp = (Get-Date -Format "yyyyMMdd-HHmmss")
$Result = Join-Path $OutDir "BOOT-$stamp.txt"
"latest=$stamp" | Set-Content -LiteralPath (Join-Path $OutDir "LATEST.txt") -Encoding ASCII

function L { param([string]$t="") $t | Add-Content -LiteralPath $Result -Encoding UTF8 }

# let PnP enumeration settle (SYSTEM task can start very early)
Start-Sleep -Seconds 25

L "Pipa boot telemetry"
L "boot stamp: $stamp"
L "lastboot: $((Get-CimInstance Win32_OperatingSystem).LastBootUpTime)"
L "host: $env:COMPUTERNAME"
L ""

L "==== DISPLAY / GPU devices ===="
Get-PnpDevice -PresentOnly |
    Where-Object { $_.Class -in @("Display","Monitor") -or $_.FriendlyName -match "Display|Graphics|GPU|Adreno|Basic" } |
    Sort-Object Class,InstanceId |
    Format-Table -AutoSize Status,Class,FriendlyName,InstanceId,Problem |
    Out-String -Width 240 | ForEach-Object { L $_ }

L ""
L "==== ALL problem devices ===="
Get-PnpDevice -PresentOnly | Where-Object { $_.Status -ne "OK" } |
    Sort-Object InstanceId |
    Format-Table -AutoSize Status,Class,FriendlyName,InstanceId,Problem |
    Out-String -Width 240 | ForEach-Object { L $_ }

L ""
L "==== target ACPI devices ===="
Get-PnpDevice -PresentOnly |
    Where-Object { $_.InstanceId -match "QCOM050D|QCOM250D|QCOM0511|QCOM2511|QCOM050F|QCOM0593|QCOM0519" } |
    Sort-Object InstanceId |
    Format-Table -AutoSize Status,Class,FriendlyName,InstanceId,Problem |
    Out-String -Width 240 | ForEach-Object { L $_ }

L ""
L "==== GIO0 detail (ACPI\QCOM050D\0) ===="
& pnputil.exe /enum-devices /instanceid "ACPI\QCOM050D\0" /drivers /properties /resources 2>&1 | ForEach-Object { L "$_" }

L ""
L "==== driver services (qcgpio qcgpi qci2c qcspi qcpep) ===="
foreach ($svc in @("qcgpio","qcgpi","qci2c","qcspi","qcpep")) {
    L "-- sc query $svc --"
    & sc.exe query $svc 2>&1 | ForEach-Object { L "$_" }
}

L ""
L "==== WMI allocated IRQ owner map ===="
try {
    $rows = @()
    Get-CimInstance -ClassName Win32_PNPAllocatedResource -ErrorAction Stop | ForEach-Object {
        $ant = "$($_.Antecedent)"; $dep = "$($_.Dependent)"
        if ($ant -match "IRQNumber\s*=\s*(\d+)") {
            $irq = [int]$Matches[1]; $devid = ""
            if ($dep -match 'DeviceID\s*=\s*"([^"]+)"') { $devid = $Matches[1] }
            $rows += [pscustomobject]@{ Irq = $irq; Dev = $devid }
        }
    }
    $rows | Sort-Object Irq | ForEach-Object { L ("IRQ {0} -> {1}" -f $_.Irq, $_.Dev) }
} catch { L "ERROR WMI IRQ: $($_.Exception.Message)" }

L ""
L "==== Kernel-PnP Configuration events (QCOM/display/conflict, last 200) ===="
try {
    Get-WinEvent -LogName "Microsoft-Windows-Kernel-PnP/Configuration" -MaxEvents 200 -ErrorAction Stop | ForEach-Object {
        $m = "$($_.Message)" -replace "\s+", " "
        if ($m -match "QCOM|conflict|0xC0000018|Display|Graphics|BasicRender|video") {
            if ($m.Length -gt 360) { $m = $m.Substring(0,360) }
            L ("[{0:o}] id={1} {2}" -f $_.TimeCreated, $_.Id, $m)
        }
    }
} catch { L "ERROR PnP events: $($_.Exception.Message)" }

"done=$stamp" | Set-Content -LiteralPath (Join-Path $OutDir "DONE-$stamp.txt") -Encoding ASCII
