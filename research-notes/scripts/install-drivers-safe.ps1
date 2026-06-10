param(
    [string]$DriverRoot = "C:\woa\drivers",
    [ValidateSet("allow", "block")]
    [string]$Mode = "allow"
)

$ErrorActionPreference = "Continue"

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Elevating to admin..."
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -DriverRoot `"$DriverRoot`" -Mode $Mode"
    exit
}

New-Item -ItemType Directory -Force -Path "C:\woa" | Out-Null
$log = "C:\woa\install-drivers.log"
"=== install-drivers START $(Get-Date -Format o) DriverRoot=$DriverRoot ===" |
    Set-Content -LiteralPath $log -Encoding UTF8

function Log {
    param([string]$Message)
    $line = "{0}  {1}" -f (Get-Date).ToString("HH:mm:ss"), $Message
    $line | Tee-Object -FilePath $log -Append
}

function Run {
    param([string]$File, [string[]]$Args)
    Log ("RUN {0} {1}" -f $File, ($Args -join " "))
    $out = & $File @Args 2>&1
    $exit = $LASTEXITCODE
    if ($out) {
        $out | Tee-Object -FilePath $log -Append
    }
    Log "EXIT $exit"
    return $exit
}

function Capture {
    param([string]$File, [string[]]$Args, [string]$OutFile)
    Log ("CAPTURE {0} {1} -> {2}" -f $File, ($Args -join " "), $OutFile)
    $out = & $File @Args 2>&1
    $exit = $LASTEXITCODE
    $out | Set-Content -LiteralPath $OutFile -Encoding UTF8
    Log "EXIT $exit"
    return $exit
}

function Set-ServiceStartIfExists {
    param([string]$ServiceName, [int]$Start)
    $path = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
    if (Test-Path -LiteralPath $path) {
        try {
            New-ItemProperty -LiteralPath $path -Name Start -PropertyType DWord -Value $Start -Force | Out-Null
            Log "SET $ServiceName Start=$Start"
        } catch {
            Log "WARN set $ServiceName Start failed: $($_.Exception.Message)"
        }
    } else {
        Log "SKIP missing service $ServiceName"
    }
}

function Disable-RiskyDrivers {
    foreach ($svc in @(
        "qcppx",
        "qcPILC",
        "qcpil",
        "qcpil8250",
        "qcpmic",
        "qcpmicapps",
        "qcpmiceic",
        "qcpmicext",
        "qcpmicglink",
        "qcpmgpio",
        "qcpmictcc",
        "qcpep",
        "qciommu",
        "qcsmmu",
        "qcscm",
        "qcwlan"
    )) {
        Set-ServiceStartIfExists -ServiceName $svc -Start 4
    }
}

Log "=== install-drivers elevated Mode=$Mode ==="
if (-not (Test-Path -LiteralPath $DriverRoot)) {
    Log "FATAL: DriverRoot tidak ada: $DriverRoot"
    pause
    exit 1
}

Disable-RiskyDrivers

$ts = (bcdedit /enum "{current}" | Select-String "testsigning\s+Yes")
if (-not $ts) {
    Log "Enabling testsigning. Reboot once, then run this script again."
    Run -File bcdedit.exe -Args @("/set", "testsigning", "on") | Out-Null
    Run -File bcdedit.exe -Args @("/set", "nointegritychecks", "on") | Out-Null
    Disable-RiskyDrivers
    pause
    exit
}
Log "testsigning already ON"

$cats = Get-ChildItem -LiteralPath $DriverRoot -Recurse -Filter *.cat -ErrorAction SilentlyContinue
Log "Found $($cats.Count) .cat files; importing signer certs"
foreach ($cat in $cats) {
    try {
        $sig = Get-AuthenticodeSignature -LiteralPath $cat.FullName
        if ($sig.SignerCertificate) {
            foreach ($storeName in @("Root", "TrustedPublisher")) {
                $store = New-Object Security.Cryptography.X509Certificates.X509Store($storeName, "LocalMachine")
                $store.Open("ReadWrite")
                $store.Add($sig.SignerCertificate)
                $store.Close()
            }
            Log "CERT OK $($cat.Name)"
        }
    } catch {
        Log "WARN cert $($cat.Name): $($_.Exception.Message)"
    }
}

$allowInf = @(
    "qcdx8250*.inf",
    "qcdx_ffu8250*.inf",
    "qdcmlib8250*.inf",
    "qcusbctcpm8250*.inf",
    "qcusbcucsi8250*.inf",
    "qcusbaudio8250*.inf",
    "nt36xxx*.inf",
    "NanosicFilter*.inf",
    "qcbattmngr8250*.inf",
    "qcbattminiclass8250*.inf"
)

$blockedInf = @(
    "qcppx*.inf",
    "qcpil*.inf",
    "*PILC*.inf",
    "qcpmic*.inf",
    "qcscm*.inf",
    "qcsmmu*.inf",
    "qciommu*.inf",
    "qcpep*.inf",
    "*mbb*.inf",
    "*wmril*.inf",
    "*qcmbb*.inf",
    "*cellular*.inf",
    "*modem*.inf",
    "*qcgnss*.inf",
    "qcwlan8250*.inf"
)

function Test-AnyPattern {
    param([string]$Name, [string[]]$Patterns)
    foreach ($pattern in $Patterns) {
        if ($Name -like $pattern) {
            return $true
        }
    }
    return $false
}

$allInfs = Get-ChildItem -LiteralPath $DriverRoot -Recurse -Filter *.inf -ErrorAction SilentlyContinue
$infs = foreach ($inf in $allInfs) {
    $name = $inf.Name
    if (Test-AnyPattern -Name $name -Patterns $blockedInf) {
        Log "BLOCK $($inf.FullName)"
        continue
    }
    if ($Mode -eq "allow" -and -not (Test-AnyPattern -Name $name -Patterns $allowInf)) {
        Log "SKIP not allowlisted $($inf.FullName)"
        continue
    }
    $inf
}
$infs = $infs | Sort-Object FullName

Log "Found $($allInfs.Count) total .inf files under $DriverRoot"
Log "Found $($infs.Count) allowed .inf files under $DriverRoot"
Log "Mode: $Mode"
Log "Allow INF patterns: $($allowInf -join ', ')"
Log "Blocked INF patterns: $($blockedInf -join ', ')"

$ok = 0
$fail = 0
foreach ($inf in $infs) {
    $out = pnputil.exe /add-driver "$($inf.FullName)" /install 2>&1
    $exit = $LASTEXITCODE
    if ($out) {
        $out | Tee-Object -FilePath $log -Append
    }
    if ($exit -eq 0 -or (($out -join "`n") -match "successfully|Already imported")) {
        $ok++
        Log "OK $($inf.FullName)"
    } else {
        $fail++
        Log "FAIL $($inf.FullName) exit=$exit"
    }
}
Log "add-driver done: OK=$ok FAIL=$fail"

Disable-RiskyDrivers
Run -File pnputil.exe -Args @("/scan-devices") | Out-Null
Disable-RiskyDrivers

Log "Dumping device state"
Capture -File pnputil.exe -Args @("/enum-devices", "/problem", "/deviceids", "/services") -OutFile "C:\woa\device-problems.txt" | Out-Null
Capture -File pnputil.exe -Args @("/enum-devices", "/connected", "/deviceids", "/services") -OutFile "C:\woa\devices-connected.txt" | Out-Null
Capture -File pnputil.exe -Args @("/enum-devices", "/deviceids", "/services") -OutFile "C:\woa\devices-all.txt" | Out-Null
Capture -File sc.exe -Args @("query", "type=", "driver", "state=", "all") -OutFile "C:\woa\driver-services.txt" | Out-Null

try {
    Get-PnpDevice |
        Where-Object { $_.Status -ne "OK" -or $_.InstanceId -match "QCOM|NTTS|NVT|NTP|VID_3206|VID_258A|VEN_QCOM|QCMS|BasicDisplay" } |
        Select-Object Status, Class, FriendlyName, InstanceId, Problem |
        Export-Csv "C:\woa\device-problems.csv" -NoTypeInformation
} catch {
    Log "WARN Get-PnpDevice CSV failed: $($_.Exception.Message)"
}

if (Test-Path -LiteralPath "C:\Windows\INF\setupapi.dev.log") {
    Get-Content -LiteralPath "C:\Windows\INF\setupapi.dev.log" -Tail 1200 |
        Set-Content -LiteralPath "C:\woa\setupapi-tail.txt" -Encoding UTF8
}

Log "DONE. Reboot once, then test keyboard/touch/GPU. Log: C:\woa\install-drivers.log"
pause

