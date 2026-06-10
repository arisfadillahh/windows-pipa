Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$Root = 'C:\woa'
$LogPath = Join-Path $Root 'woa-fix.log'
$ResultPath = Join-Path $Root 'RESULT.txt'

New-Item -ItemType Directory -Path $Root -Force | Out-Null
"=== WOA FIX START $(Get-Date -Format o) ===" | Set-Content -LiteralPath $LogPath -Encoding UTF8

function Log {
    param([string]$Message)
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $line | Tee-Object -FilePath $LogPath -Append
}

function Run {
    param(
        [string]$File,
        [string[]]$ArgumentList
    )
    if ($null -eq $ArgumentList) {
        $ArgumentList = @()
    }
    Log ('RUN {0} {1}' -f $File, ($ArgumentList -join ' '))
    $output = & $File @ArgumentList 2>&1
    $exit = $LASTEXITCODE
    if ($output) {
        $output | Tee-Object -FilePath $LogPath -Append
    }
    Log ("EXIT $exit")
    return $exit
}

function Capture {
    param(
        [string]$File,
        [string[]]$ArgumentList,
        [string]$OutFile
    )
    if ($null -eq $ArgumentList) {
        $ArgumentList = @()
    }
    Log ('CAPTURE {0} {1} -> {2}' -f $File, ($ArgumentList -join ' '), $OutFile)
    $output = & $File @ArgumentList 2>&1
    $exit = $LASTEXITCODE
    $output | Set-Content -LiteralPath (Join-Path $Root $OutFile) -Encoding UTF8
    Log ("EXIT $exit")
    return $exit
}

function Set-Dword {
    param(
        [string]$Path,
        [string]$Name,
        [int]$Value
    )
    try {
        New-Item -Path $Path -Force | Out-Null
        New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
        Log "SET $Path $Name=$Value"
    } catch {
        Log "WARN set registry failed: $Path $Name $($_.Exception.Message)"
    }
}

Log 'Patching OOBE/local-account registry values'
Set-Dword 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' 'BypassNRO' 1
Set-Dword 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' 'DefaultAccountAction' 0
Set-Dword 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' 'LaunchUserOOBE' 0
Set-Dword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE' 'DisablePrivacyExperience' 1

Log 'Ensuring test-signing is enabled for adapted/unsigned drivers'
Run -File bcdedit.exe -ArgumentList @('/set', 'testsigning', 'on') | Out-Null

Log 'Keeping known boot-break drivers disabled for now'
Run -File reg.exe -ArgumentList @('add', 'HKLM\SYSTEM\CurrentControlSet\Services\qcppx', '/v', 'Start', '/t', 'REG_DWORD', '/d', '4', '/f') | Out-Null
Run -File reg.exe -ArgumentList @('add', 'HKLM\SYSTEM\CurrentControlSet\Services\qcPILC', '/v', 'Start', '/t', 'REG_DWORD', '/d', '4', '/f') | Out-Null

$DriverPackageRoots = @(
    'C:\woa\PipaDrivers',
    'C:\PipaDrivers',
    'C:\woa\PartnerDrivers',
    'C:\PartnerDrivers'
) | Where-Object { Test-Path -LiteralPath $_ }

$DriverRoots = @(
    $DriverPackageRoots
    'C:\Windows\System32\DriverStore\FileRepository'
) | Where-Object { Test-Path -LiteralPath $_ }

$CatNamePatterns = @(
    'qcscm',
    'qcspmi',
    'qcabd',
    'qcpmic',
    'nt36xxx',
    'nanosicfilter',
    'qcImproveTouch',
    'qci2c',
    'qcdx',
    'qcwlan',
    'qcbatt',
    'qcusb',
    'qcsensors',
    'qcbt'
)

Log 'Importing signer certs from targeted driver catalogs when available'
foreach ($rootPath in $DriverRoots) {
    foreach ($cat in Get-ChildItem -LiteralPath $rootPath -Recurse -Filter '*.cat' -ErrorAction SilentlyContinue) {
        $matched = $false
        foreach ($pattern in $CatNamePatterns) {
            if ($cat.Name -like "$pattern*") {
                $matched = $true
                break
            }
        }
        if (-not $matched) {
            continue
        }

        try {
            $sig = Get-AuthenticodeSignature -LiteralPath $cat.FullName
            if ($null -eq $sig.SignerCertificate) {
                Log "NO CERT $($cat.FullName)"
                continue
            }

            $certPath = Join-Path $Root ("cert-{0}.cer" -f $sig.SignerCertificate.Thumbprint)
            Export-Certificate -Cert $sig.SignerCertificate -FilePath $certPath -Force | Out-Null
            Import-Certificate -FilePath $certPath -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
            Import-Certificate -FilePath $certPath -CertStoreLocation Cert:\LocalMachine\TrustedPublisher | Out-Null
            Log "IMPORTED CERT $($cat.Name) $($sig.SignerCertificate.Thumbprint)"
        } catch {
            Log "WARN cert import failed for $($cat.FullName): $($_.Exception.Message)"
        }
    }
}

$TargetDriverDirs = foreach ($driverRoot in $DriverPackageRoots) {
    Join-Path $driverRoot 'Drivers\SOC\System\SCM'
    Join-Path $driverRoot 'Drivers\SOC\SPMI'
    Join-Path $driverRoot 'Drivers\SOC\ACPI'
    Join-Path $driverRoot 'Drivers\SOC\PMIC'
    Join-Path $driverRoot 'Drivers\SOC\I2C'
    Join-Path $driverRoot 'Drivers\SOC\XMKB'
    Join-Path $driverRoot 'Drivers\Touch'
    Join-Path $driverRoot 'Drivers\Graphics'
    Join-Path $driverRoot 'Drivers\USB'
    Join-Path $driverRoot 'Drivers\Sensors'
    Join-Path $driverRoot 'Drivers\Battery'
    Join-Path $driverRoot 'Drivers\Bluetooth'
    Join-Path $driverRoot 'Drivers\WLAN'
    Join-Path $driverRoot 'kona-drivers\Drivers\SOC\System\SCM'
    Join-Path $driverRoot 'kona-drivers\Drivers\SOC\SPMI'
    Join-Path $driverRoot 'kona-drivers\Drivers\SOC\ACPI'
    Join-Path $driverRoot 'kona-drivers\Drivers\SOC\PMIC'
    Join-Path $driverRoot 'kona-drivers\Drivers\SOC\I2C'
    Join-Path $driverRoot 'kona-drivers\Drivers\Touch'
    Join-Path $driverRoot 'kona-drivers\Drivers\Graphics'
    Join-Path $driverRoot 'kona-drivers\Drivers\USB'
    Join-Path $driverRoot 'kona-drivers\Drivers\Sensors'
    Join-Path $driverRoot 'kona-drivers\Drivers\Battery'
    Join-Path $driverRoot 'kona-drivers\Drivers\Bluetooth'
    Join-Path $driverRoot 'kona-drivers\Drivers\WLAN'
    Join-Path $driverRoot 'pad6-keyboard-driver'
    Join-Path $driverRoot 'pad6-touch-driver'
}

Log 'Adding targeted drivers from copied PipaDrivers folders'
foreach ($dir in $TargetDriverDirs) {
    if (Test-Path -LiteralPath $dir) {
        Run -File pnputil.exe -ArgumentList @('/add-driver', (Join-Path $dir '*.inf'), '/subdirs', '/install') | Out-Null
    } else {
        Log "SKIP missing $dir"
    }
}

Log 'Trying already-staged DriverStore INF packages'
$StoreInfPatterns = @(
    'qcscm*.inf',
    'qcspmi*.inf',
    'qcabd*.inf',
    'qcpmic*.inf',
    'nt36xxx*.inf',
    'qci2c*.inf',
    'qcImproveTouch*.inf',
    'qcdx*.inf',
    'qcwlan*.inf',
    'NanosicFilter*.inf',
    'qcbatt*.inf',
    'qcusb*.inf',
    'qcsensors*.inf',
    'qcbtfm*.inf'
)
foreach ($filter in $StoreInfPatterns) {
    foreach ($inf in Get-ChildItem -LiteralPath 'C:\Windows\System32\DriverStore\FileRepository' -Recurse -Filter $filter -ErrorAction SilentlyContinue) {
        Run -File pnputil.exe -ArgumentList @('/add-driver', $inf.FullName, '/install') | Out-Null
    }
}

Log 'Scanning devices'
Run -File pnputil.exe -ArgumentList @('/scan-devices') | Out-Null

Log 'Re-disabling known boot-break drivers after package import'
Run -File reg.exe -ArgumentList @('add', 'HKLM\SYSTEM\CurrentControlSet\Services\qcppx', '/v', 'Start', '/t', 'REG_DWORD', '/d', '4', '/f') | Out-Null
Run -File reg.exe -ArgumentList @('add', 'HKLM\SYSTEM\CurrentControlSet\Services\qcPILC', '/v', 'Start', '/t', 'REG_DWORD', '/d', '4', '/f') | Out-Null

$Services = @(
    'qcscm',
    'qcspmi',
    'qcABD',
    'qcpmic',
    'qcpmicext',
    'qcpmgpio',
    'nt36xxx',
    'qci2c',
    'qcImproveTouch',
    'QCDX',
    'qcwlan',
    'NanosicFilter'
)
Log 'Configuring and starting targeted demand-start services'
foreach ($service in $Services) {
    Run -File sc.exe -ArgumentList @('query', $service) | Out-Null
    Run -File sc.exe -ArgumentList @('config', $service, 'start=', 'demand') | Out-Null
    Run -File sc.exe -ArgumentList @('start', $service) | Out-Null
}

Log 'Final service status'
foreach ($service in $Services) {
    Run -File sc.exe -ArgumentList @('query', $service) | Out-Null
}

Log 'Dumping live device state'
Capture -File pnputil.exe -ArgumentList @('/enum-devices', '/connected', '/deviceids', '/services') -OutFile 'devices-connected.txt' | Out-Null
Capture -File pnputil.exe -ArgumentList @('/enum-devices', '/deviceids', '/services') -OutFile 'devices-all.txt' | Out-Null
Capture -File pnputil.exe -ArgumentList @('/enum-devices', '/problem', '/deviceids', '/services') -OutFile 'devices-problem.txt' | Out-Null
Capture -File sc.exe -ArgumentList @('query', 'type=', 'driver', 'state=', 'all') -OutFile 'driver-services.txt' | Out-Null

try {
    Get-PnpDevice -PresentOnly |
        Where-Object {
            $_.InstanceId -match 'QCOM|NTTS|NVT|NTP|VID_3206|VID_258A|VEN_QCOM|QCMS|BasicDisplay'
        } |
        Select-Object Status, Class, FriendlyName, InstanceId, Problem |
        Format-List |
        Set-Content -LiteralPath (Join-Path $Root 'pnp-interesting.txt') -Encoding UTF8
} catch {
    Log "WARN Get-PnpDevice interesting dump failed: $($_.Exception.Message)"
}

if (Test-Path -LiteralPath 'C:\Windows\INF\setupapi.dev.log') {
    Get-Content -LiteralPath 'C:\Windows\INF\setupapi.dev.log' -Tail 800 |
        Set-Content -LiteralPath (Join-Path $Root 'setupapi-tail.txt') -Encoding UTF8
}

@"
WOA fix script finished.

Try these now:
1. Reboot Windows once if a driver prompt asked for it.
2. If touch/GPU/Wi-Fi/keyboard still does not work, fastboot the tablet and let Codex read C:\woa logs.
3. Do not enable qcppx yet.

Log: C:\woa\woa-fix.log
"@ | Set-Content -LiteralPath $ResultPath -Encoding UTF8

Log "DONE. Result: $ResultPath"
"=== WOA FIX END $(Get-Date -Format o) ===" | Add-Content -LiteralPath $LogPath
Write-Host ''
Write-Host 'WOA fix done. Log: C:\woa\woa-fix.log'
Write-Host 'If local account window appears, continue setup there.'
pause

