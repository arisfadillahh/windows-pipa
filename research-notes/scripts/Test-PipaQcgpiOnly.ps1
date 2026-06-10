param(
    [string] $Root = 'C:\woa\qcgpi-only'
)

$ErrorActionPreference = 'Continue'
$LogPath = Join-Path $Root 'test-qcgpi-only.log'
$ResultPath = Join-Path $Root 'RESULT.txt'
$DonePath = Join-Path $Root 'DONE.txt'
$InfPath = Join-Path $Root 'driver\qcgpi8150.inf'
$CertPath = Join-Path $Root 'woa-kmci-leaf.cer'
$InstanceId = 'ACPI\QCOM0593\0'

function Log {
    param([string] $Message)
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $line | Tee-Object -FilePath $LogPath -Append
}

function Run {
    param([string] $File, [string[]] $Arguments)
    Log ("RUN {0} {1}" -f $File, ($Arguments -join ' '))
    & $File @Arguments 2>&1 | Tee-Object -FilePath $LogPath -Append
    $code = $LASTEXITCODE
    Log "$File exit code: $code"
    return $code
}

function Dump-Target {
    param([string] $Name)
    $dir = Join-Path $Root $Name
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    cmd.exe /c "pnputil /enum-devices /instanceid `"$InstanceId`" /ids /drivers > `"$dir\pnputil.txt`" 2>&1"
    Get-PnpDevice -InstanceId $InstanceId -ErrorAction SilentlyContinue |
        Format-List Status,Class,FriendlyName,InstanceId,Problem |
        Out-File -LiteralPath (Join-Path $dir 'get-pnp.txt') -Encoding utf8
    Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
        Where-Object DeviceID -eq $InstanceId |
        Select-Object Status,PNPClass,Name,DeviceID,ConfigManagerErrorCode,Service |
        Export-Csv -LiteralPath (Join-Path $dir 'cim-pnp.csv') -NoTypeInformation
    sc.exe query qcGPI 2>&1 |
        Out-File -LiteralPath (Join-Path $dir 'service-qcgpi.txt') -Encoding utf8
}

New-Item -ItemType Directory -Force -Path $Root | Out-Null
if (Test-Path -LiteralPath $DonePath) {
    exit 0
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Log 'Requesting UAC for isolated QCGPI test.'
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Root `"$Root`""
    Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments -Wait
    exit 0
}

"=== PIPA QCGPI-ONLY TEST START $(Get-Date -Format o) ===" |
    Set-Content -LiteralPath $LogPath -Encoding UTF8
Log "Running elevated as $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Log "Target instance: $InstanceId"

if (-not (Test-Path -LiteralPath $InfPath)) {
    Log "MISSING: $InfPath"
    "FAILED: driver INF missing: $InfPath" | Set-Content -LiteralPath $ResultPath
    exit 2
}

if (Test-Path -LiteralPath $CertPath) {
    Log 'Importing WOA KMCI signer into LocalMachine Root and TrustedPublisher.'
    Import-Certificate -FilePath $CertPath -CertStoreLocation Cert:\LocalMachine\Root 2>&1 |
        Tee-Object -FilePath $LogPath -Append | Out-Null
    Import-Certificate -FilePath $CertPath -CertStoreLocation Cert:\LocalMachine\TrustedPublisher 2>&1 |
        Tee-Object -FilePath $LogPath -Append | Out-Null
} else {
    Log "Signer certificate missing: $CertPath"
}

$signature = Get-AuthenticodeSignature -LiteralPath (Join-Path $Root 'driver\qcgpi8150.cat')
Log "Catalog signature status: $($signature.Status)"
Dump-Target 'before'

$installExit = Run pnputil.exe @('/add-driver', $InfPath, '/install')
Start-Sleep -Seconds 8
Dump-Target 'after'

$target = Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
    Where-Object DeviceID -eq $InstanceId |
    Select-Object -First 1
$service = Get-CimInstance Win32_SystemDriver -Filter "Name='qcGPI'" -ErrorAction SilentlyContinue

$result = @(
    'Pipa isolated QCGPI driver test'
    "Completed: $(Get-Date -Format o)"
    "pnputil exit: $installExit"
    "Device: $InstanceId"
    "Device name: $($target.Name)"
    "ConfigManagerErrorCode: $($target.ConfigManagerErrorCode)"
    "Service: $($target.Service)"
    "qcGPI state: $($service.State)"
    "qcGPI start mode: $($service.StartMode)"
    ''
    'No reboot was requested. Do not install another driver yet.'
)
$result | Set-Content -LiteralPath $ResultPath -Encoding UTF8
"DONE $(Get-Date -Format o)" | Set-Content -LiteralPath $DonePath -Encoding ASCII
Log "RESULT: pnputil=$installExit code=$($target.ConfigManagerErrorCode) service=$($target.Service) state=$($service.State)"
Log 'QCGPI_ONLY_TEST_DONE'
$startupFallback = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Startup\Codex-QCGPI-Only.cmd'
if (Test-Path -LiteralPath $startupFallback) {
    Remove-Item -LiteralPath $startupFallback -Force -ErrorAction SilentlyContinue
    Log 'Removed Startup fallback.'
}
"=== PIPA QCGPI-ONLY TEST END $(Get-Date -Format o) ===" |
    Add-Content -LiteralPath $LogPath

Start-Process notepad.exe -ArgumentList "`"$ResultPath`""

