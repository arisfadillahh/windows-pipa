param(
    [string] $Root = 'C:\woa\qcspi-only'
)

$ErrorActionPreference = 'Continue'
$LogPath = Join-Path $Root 'test-qcspi-only.log'
$ResultPath = Join-Path $Root 'RESULT.txt'
$DonePath = Join-Path $Root 'DONE.txt'
$AttemptPath = Join-Path $Root 'ATTEMPTED.txt'
$InfPath = Join-Path $Root 'driver\qcspi8250.inf'
$CatPath = Join-Path $Root 'driver\qcspi8250.cat'
$HardwareId = 'ACPI\QCOM050F'
$CompatibleId = 'ACPI\QCOM250F'
$ServiceName = 'qcspi'

function Log {
    param([string] $Message)
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $line | Tee-Object -FilePath $LogPath -Append
}

function Get-Target {
    Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
        Where-Object DeviceID -Like "$HardwareId\*" |
        Select-Object -First 1
}

function Dump-Target {
    param([string] $Name)
    $dir = Join-Path $Root $Name
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $target = Get-Target
    if ($target) {
        cmd.exe /c "pnputil /enum-devices /instanceid `"$($target.DeviceID)`" /ids /drivers > `"$dir\pnputil.txt`" 2>&1"
        Get-PnpDevice -InstanceId $target.DeviceID -ErrorAction SilentlyContinue |
            Format-List Status,Class,FriendlyName,InstanceId,Problem |
            Out-File -LiteralPath (Join-Path $dir 'get-pnp.txt') -Encoding utf8
        $target |
            Select-Object Status,PNPClass,Name,DeviceID,ConfigManagerErrorCode,Service |
            Export-Csv -LiteralPath (Join-Path $dir 'cim-pnp.csv') -NoTypeInformation
    } else {
        "Target not found: $HardwareId" |
            Set-Content -LiteralPath (Join-Path $dir 'target-not-found.txt') -Encoding UTF8
    }
    sc.exe query $ServiceName 2>&1 |
        Out-File -LiteralPath (Join-Path $dir 'service-qcspi.txt') -Encoding utf8
    Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
        Where-Object { $_.DeviceID -match 'NVT36532|NTTS3652|NTP36532' } |
        Select-Object Status,PNPClass,Name,DeviceID,ConfigManagerErrorCode,Service |
        Export-Csv -LiteralPath (Join-Path $dir 'possible-touch-children.csv') -NoTypeInformation
}

function Remove-StartupFallback {
    $startupFallback = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Startup\Codex-QCSPI-Only.cmd'
    if (Test-Path -LiteralPath $startupFallback) {
        Remove-Item -LiteralPath $startupFallback -Force -ErrorAction SilentlyContinue
        Log 'Removed Startup fallback.'
    }
}

New-Item -ItemType Directory -Force -Path $Root | Out-Null
if (Test-Path -LiteralPath $DonePath) {
    exit 0
}
if (Test-Path -LiteralPath $AttemptPath) {
    "SKIPPED: QCSPI test already attempted. Remove ATTEMPTED.txt manually to retry." |
        Set-Content -LiteralPath $ResultPath -Encoding UTF8
    Remove-StartupFallback
    exit 0
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Log 'Requesting UAC for isolated QCSPI test.'
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Root `"$Root`""
    Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments -Wait
    exit 0
}

"=== PIPA QCSPI-ONLY TEST START $(Get-Date -Format o) ===" |
    Set-Content -LiteralPath $LogPath -Encoding UTF8
Log "Running elevated as $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Log "Target hardware ID: $HardwareId"
Log "Expected compatible ID: $CompatibleId"
"ATTEMPTED $(Get-Date -Format o)" | Set-Content -LiteralPath $AttemptPath -Encoding ASCII
Remove-StartupFallback

if (-not (Test-Path -LiteralPath $InfPath) -or -not (Test-Path -LiteralPath $CatPath)) {
    Log "MISSING signed package: $InfPath or $CatPath"
    "FAILED: signed driver package missing" | Set-Content -LiteralPath $ResultPath
    Remove-StartupFallback
    exit 2
}

$catalogSignature = Get-AuthenticodeSignature -LiteralPath $CatPath
Log "Catalog signature status: $($catalogSignature.Status)"
Log "Catalog signer: $($catalogSignature.SignerCertificate.Subject)"

$targetBefore = Get-Target
if (-not $targetBefore) {
    Log "FAILED: target not found: $HardwareId"
    "FAILED: target not found: $HardwareId" | Set-Content -LiteralPath $ResultPath
    Remove-StartupFallback
    Start-Process notepad.exe -ArgumentList "`"$ResultPath`""
    exit 3
}

Log "Target instance: $($targetBefore.DeviceID)"
Dump-Target 'before'

Log "RUN pnputil.exe /add-driver $InfPath /install"
$installOutput = @(& pnputil.exe /add-driver $InfPath /install 2>&1)
$installExit = $LASTEXITCODE
$installOutput | Tee-Object -FilePath $LogPath -Append | Out-Null
Log "pnputil.exe exit code: $installExit"
$restartMentioned = [bool]($installOutput | Where-Object { "$_" -match '(?i)restart' })

Start-Sleep -Seconds 10
Dump-Target 'after'

$target = Get-Target
$service = Get-CimInstance Win32_SystemDriver -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
$touch = Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
    Where-Object { $_.DeviceID -match 'NVT36532|NTTS3652|NTP36532' } |
    Select-Object -First 1

$result = @(
    'Pipa isolated QCSPI driver test'
    "Completed: $(Get-Date -Format o)"
    "pnputil exit: $installExit"
    "Install output mentioned restart: $restartMentioned"
    "Catalog signature status: $($catalogSignature.Status)"
    "Catalog signer: $($catalogSignature.SignerCertificate.Subject)"
    "Expected compatible ID: $CompatibleId"
    "Device: $($target.DeviceID)"
    "Device name: $($target.Name)"
    "ConfigManagerErrorCode: $($target.ConfigManagerErrorCode)"
    "Service: $($target.Service)"
    "qcspi state: $($service.State)"
    "qcspi start mode: $($service.StartMode)"
    "Possible touch child: $($touch.DeviceID)"
    "Possible touch child code: $($touch.ConfigManagerErrorCode)"
    ''
    'No system reboot was requested. Do not install another driver yet.'
)
$result | Set-Content -LiteralPath $ResultPath -Encoding UTF8
"DONE $(Get-Date -Format o)" | Set-Content -LiteralPath $DonePath -Encoding ASCII
Log "RESULT: pnputil=$installExit code=$($target.ConfigManagerErrorCode) service=$($target.Service) state=$($service.State) restartMentioned=$restartMentioned"
Log 'QCSPI_ONLY_TEST_DONE'
Remove-StartupFallback
"=== PIPA QCSPI-ONLY TEST END $(Get-Date -Format o) ===" |
    Add-Content -LiteralPath $LogPath

Start-Process notepad.exe -ArgumentList "`"$ResultPath`""

