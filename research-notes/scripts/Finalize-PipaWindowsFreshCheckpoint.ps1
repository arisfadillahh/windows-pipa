$ErrorActionPreference = 'Stop'
$LogPath = '<ARTIFACT_DIR>\fresh-reinstall-finalize-20260604.log'
$WinRoot = 'W:\'
$EspRoot = 'Z:\'

function Log {
    param([string] $Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $line | Tee-Object -FilePath $LogPath -Append
}

function Run-Reg {
    param([string[]] $Arguments)
    & reg.exe @Arguments 2>&1 | Tee-Object -FilePath $LogPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "reg.exe $($Arguments -join ' ') exited with $LASTEXITCODE"
    }
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

"=== PIPA FRESH FINALIZE START $(Get-Date -Format o) ===" |
    Set-Content -LiteralPath $LogPath -Encoding UTF8

if ((Get-Volume -DriveLetter W).FileSystemLabel -ne 'WINPIPA') {
    throw 'W: is not WINPIPA'
}
$esp = Get-Partition -DriveLetter Z
if ($esp.PartitionNumber -ne 35 -or $esp.GptType -ne '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}') {
    throw 'Z: is not pipa ESP partition 35'
}

$required = @(
    'W:\Windows\System32\Config\SYSTEM',
    'W:\Windows\System32\Config\SOFTWARE',
    'W:\Windows\Panther\unattend.xml',
    'W:\Windows\Setup\Scripts\SetupComplete.cmd',
    'W:\woa\continue-driver-checkpoint.ps1',
    'W:\woa\install-drivers-no-power.ps1',
    'W:\woa\dump-woa-status.ps1',
    'W:\woa\CHECKPOINT.md',
    'Z:\EFI\Microsoft\Boot\BCD'
)
foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required staged file missing: $path"
    }
}
Log 'Staged files verified'

& reg.exe unload HKLM\PIPA_FRESH_SYSTEM 2>$null | Out-Null
& reg.exe unload HKLM\PIPA_FRESH_SOFTWARE 2>$null | Out-Null

try {
    Run-Reg @('load', 'HKLM\PIPA_FRESH_SYSTEM', 'W:\Windows\System32\Config\SYSTEM')
    Run-Reg @('add', 'HKLM\PIPA_FRESH_SYSTEM\ControlSet001\Control\USB', '/v', 'OsDefaultRoleSwitchMode', '/t', 'REG_DWORD', '/d', '1', '/f')
} finally {
    & reg.exe unload HKLM\PIPA_FRESH_SYSTEM 2>&1 | Tee-Object -FilePath $LogPath -Append
}
Log 'Offline SYSTEM USB role patched'

try {
    Run-Reg @('load', 'HKLM\PIPA_FRESH_SOFTWARE', 'W:\Windows\System32\Config\SOFTWARE')
    Run-Reg @('add', 'HKLM\PIPA_FRESH_SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE', '/v', 'BypassNRO', '/t', 'REG_DWORD', '/d', '1', '/f')
    Run-Reg @('add', 'HKLM\PIPA_FRESH_SOFTWARE\Policies\Microsoft\Windows\OOBE', '/v', 'DisablePrivacyExperience', '/t', 'REG_DWORD', '/d', '1', '/f')
} finally {
    & reg.exe unload HKLM\PIPA_FRESH_SOFTWARE 2>&1 | Tee-Object -FilePath $LogPath -Append
}
Log 'Offline SOFTWARE OOBE fallback patched'

$manifest = [ordered]@{
    FinalizedAt = (Get-Date -Format o)
    User = 'Goffath'
    AndroidPartitionUntouched = 34
    EspPartitionFormatted = 35
    WindowsPartitionFormatted = 36
    StableUefiToRestore = '<ARTIFACT_DIR>\pipa_muold_touchmin_v8.img'
    DriverContinuationTask = 'Pipa WOA Driver Continuation'
    DriverMode = 'no-power allowlist: GPU, touch, keyboard'
    AutomaticRebootAfterDriverInstall = $false
}
$manifest | ConvertTo-Json |
    Set-Content -LiteralPath 'W:\woa\fresh-install-manifest.json' -Encoding UTF8

$hashes = Get-FileHash -Algorithm SHA256 -LiteralPath @(
    'W:\Windows\Panther\unattend.xml',
    'W:\Windows\Setup\Scripts\SetupComplete.cmd',
    'W:\woa\continue-driver-checkpoint.ps1',
    'W:\woa\install-drivers-no-power.ps1',
    'W:\woa\CHECKPOINT.md',
    'Z:\EFI\Microsoft\Boot\BCD'
)
$hashes | Format-Table -AutoSize | Out-String | Tee-Object -FilePath $LogPath -Append

Log 'FINALIZE_DONE'
"=== PIPA FRESH FINALIZE END $(Get-Date -Format o) ===" |
    Add-Content -LiteralPath $LogPath

