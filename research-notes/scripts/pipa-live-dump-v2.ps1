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
    "Pipa live PnP dump v2 (devices + arbiter + events)" | Set-Content -LiteralPath $Result -Encoding UTF8
    Add-Line "started: $(Get-Date -Format o)"
    Add-Line "user: $env:USERDOMAIN\$env:USERNAME"
    Add-Line "image expected: v25-i2c2-irq635 (or v19 baseline if rolled back)"
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

    Add-Line ""
    Add-Line "==== all problem devices ===="
    Get-PnpDevice -PresentOnly |
        Where-Object { $_.Status -ne "OK" } |
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

    Add-Line ""
    Add-Line "==== WMI allocated IRQ owner map ===="
    try {
        $irqRows = @()
        Get-CimInstance -ClassName Win32_PNPAllocatedResource -ErrorAction Stop | ForEach-Object {
            $ant = "$($_.Antecedent)"
            $dep = "$($_.Dependent)"
            if ($ant -match "IRQNumber\s*=\s*(\d+)") {
                $irq = [int]$Matches[1]
                $devid = ""
                if ($dep -match 'DeviceID\s*=\s*"([^"]+)"') { $devid = $Matches[1] }
                $irqRows += [pscustomobject]@{ Irq = $irq; Dev = $devid }
            }
        }
        $irqRows | Sort-Object Irq | ForEach-Object { Add-Line ("IRQ {0} -> {1}" -f $_.Irq, $_.Dev) }
        Add-Line ("total allocated IRQ rows: {0}" -f $irqRows.Count)
    }
    catch {
        Add-Line "ERROR WMI IRQ: $($_.Exception.Message)"
    }

    Add-Line ""
    Add-Line "==== WMI allocated memory owner map (0x00900000-0x009FFFFF, 0x0F000000-0x0FFFFFFF) ===="
    try {
        Get-CimInstance -ClassName Win32_PNPAllocatedResource -ErrorAction Stop | ForEach-Object {
            $ant = "$($_.Antecedent)"
            $dep = "$($_.Dependent)"
            if ($ant -match "Win32_DeviceMemoryAddress" -and $ant -match 'StartingAddress\s*=\s*"?(\d+)"?') {
                $start = [uint64]$Matches[1]
                if (($start -ge 9437184 -and $start -le 10485759) -or ($start -ge 251658240 -and $start -le 268435455)) {
                    $devid = ""
                    if ($dep -match 'DeviceID\s*=\s*"([^"]+)"') { $devid = $Matches[1] }
                    Add-Line ("MEM 0x{0:X} -> {1}" -f $start, $devid)
                }
            }
        }
    }
    catch {
        Add-Line "ERROR WMI MEM: $($_.Exception.Message)"
    }

    Add-Line ""
    Add-Line "==== Kernel-PnP Configuration events (QCOM/conflict, last 300) ===="
    try {
        Get-WinEvent -LogName "Microsoft-Windows-Kernel-PnP/Configuration" -MaxEvents 300 -ErrorAction Stop | ForEach-Object {
            $m = "$($_.Message)" -replace "\s+", " "
            if ($m -match "QCOM|conflict|0xC0000018") {
                if ($m.Length -gt 380) { $m = $m.Substring(0, 380) }
                Add-Line ("[{0:o}] id={1} {2}" -f $_.TimeCreated, $_.Id, $m)
            }
        }
    }
    catch {
        Add-Line "ERROR PnP events: $($_.Exception.Message)"
    }

    Add-Line ""
    Add-Line "==== System log PnP/ACPI events (filtered, last 400) ===="
    try {
        Get-WinEvent -FilterHashtable @{ LogName = "System" } -MaxEvents 400 -ErrorAction Stop | ForEach-Object {
            if ($_.ProviderName -match "Kernel-PnP|PlugPlay|ACPI|UserPnp") {
                $m = "$($_.Message)" -replace "\s+", " "
                if ($m -match "QCOM|conflict|resource") {
                    if ($m.Length -gt 380) { $m = $m.Substring(0, 380) }
                    Add-Line ("[{0:o}] {1} id={2} {3}" -f $_.TimeCreated, $_.ProviderName, $_.Id, $m)
                }
            }
        }
    }
    catch {
        Add-Line "ERROR System events: $($_.Exception.Message)"
    }

    "completed=$(Get-Date -Format o)" | Set-Content -LiteralPath (Join-Path $OutDir "DONE.txt") -Encoding ASCII
}
catch {
    "error=$($_.Exception.Message)" | Set-Content -LiteralPath (Join-Path $OutDir "ERROR.txt") -Encoding ASCII
}
finally {
    Remove-Item -LiteralPath $Running -Force -ErrorAction SilentlyContinue
}
