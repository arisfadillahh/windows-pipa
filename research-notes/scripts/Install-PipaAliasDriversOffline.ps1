Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$ImageRoot = 'E:\'
$LogPath = '<ARTIFACT_DIR>\install-pipa-qcom05xx-alias-dism.log'
$DriverDirs = @(
    'E:\woa\PipaDrivers\Drivers\SOC\System\SCM',
    'E:\woa\PipaDrivers\Drivers\SOC\SPMI',
    'E:\woa\PipaDrivers\Drivers\SOC\ACPI',
    'E:\woa\PipaDrivers\Drivers\SOC\PMIC\Core',
    'E:\woa\PipaDrivers\Drivers\SOC\PMIC\Extension',
    'E:\woa\PipaDrivers\Drivers\SOC\PMIC\GPIO'
)

"=== PIPA QCOM05XX ALIAS OFFLINE INSTALL $(Get-Date -Format o) ===" |
    Set-Content -LiteralPath $LogPath -Encoding UTF8

function Log {
    param([string]$Message)
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $line | Tee-Object -FilePath $LogPath -Append
}

function Run {
    param([string]$File, [string[]]$ArgumentList)
    Log ('RUN {0} {1}' -f $File, ($ArgumentList -join ' '))
    $output = & $File @ArgumentList 2>&1
    $exit = $LASTEXITCODE
    if ($output) {
        $output | Tee-Object -FilePath $LogPath -Append
    }
    Log "EXIT $exit"
    return $exit
}

if (-not (Test-Path -LiteralPath (Join-Path $ImageRoot 'Windows\System32\Config\SYSTEM'))) {
    Log "ERROR: Windows image not found at $ImageRoot"
    exit 2
}

foreach ($dir in $DriverDirs) {
    if (Test-Path -LiteralPath $dir) {
        Run -File dism.exe -ArgumentList @('/Image:E:\', '/Add-Driver', "/Driver:$dir", '/Recurse', '/ForceUnsigned') | Out-Null
    } else {
        Log "SKIP missing $dir"
    }
}

$hiveLoaded = $false
Run -File reg.exe -ArgumentList @('load', 'HKLM\PIPA_SYSTEM', 'E:\Windows\System32\Config\SYSTEM') | Out-Null
if ($LASTEXITCODE -eq 0) {
    $hiveLoaded = $true
    $controlSet = 'HKLM:\PIPA_SYSTEM\ControlSet001\Services'
    $demandServices = @('qcscm', 'qcspmi', 'qcABD', 'qcpmic', 'qcpmicext', 'qcpmgpio')
    foreach ($service in $demandServices) {
        $path = Join-Path $controlSet $service
        if (Test-Path -LiteralPath $path) {
            New-ItemProperty -LiteralPath $path -Name Start -PropertyType DWord -Value 3 -Force | Out-Null
            Log "SET $service Start=3"
        }
    }
    foreach ($service in @('qcppx', 'qcPILC')) {
        $path = Join-Path $controlSet $service
        if (Test-Path -LiteralPath $path) {
            New-ItemProperty -LiteralPath $path -Name Start -PropertyType DWord -Value 4 -Force | Out-Null
            Log "KEEP $service Start=4"
        }
    }
}

if ($hiveLoaded) {
    [gc]::Collect()
    Start-Sleep -Seconds 1
    Run -File reg.exe -ArgumentList @('unload', 'HKLM\PIPA_SYSTEM') | Out-Null
}

Log 'DONE'
"=== END $(Get-Date -Format o) ===" | Add-Content -LiteralPath $LogPath

