Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$LogPath = '<ARTIFACT_DIR>\fix-offline-registry-unload-20260601.log'
"=== PIPA OFFLINE REGISTRY FIX START $(Get-Date -Format o) ===" | Set-Content -LiteralPath $LogPath -Encoding UTF8

function Log($Message) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $line | Tee-Object -FilePath $LogPath -Append
}

function Run-Reg([string[]]$Arguments) {
    Log ("RUN reg.exe " + ($Arguments -join ' '))
    $output = & reg.exe @Arguments 2>&1
    $exit = $LASTEXITCODE
    $output | Tee-Object -FilePath $LogPath -Append
    if ($exit -ne 0) {
        throw "reg.exe failed with exit code $exit"
    }
}

function Ensure-HiveLoaded([string]$Name, [string]$HivePath) {
    & reg.exe query "HKLM\$Name" *> $null
    if ($LASTEXITCODE -eq 0) {
        Log "$Name already loaded"
        return
    }
    Run-Reg @('load', "HKLM\$Name", $HivePath)
}

Ensure-HiveLoaded 'PIPA_SYSTEM' 'E:\Windows\System32\Config\SYSTEM'
Ensure-HiveLoaded 'PIPA_SOFTWARE' 'E:\Windows\System32\Config\SOFTWARE'

Run-Reg @('add', 'HKLM\PIPA_SYSTEM\ControlSet001\Control\USB', '/v', 'OsDefaultRoleSwitchMode', '/t', 'REG_DWORD', '/d', '1', '/f')
Run-Reg @('add', 'HKLM\PIPA_SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE', '/v', 'DefaultAccountAction', '/t', 'REG_DWORD', '/d', '0', '/f')
Run-Reg @('add', 'HKLM\PIPA_SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE', '/v', 'LaunchUserOOBE', '/t', 'REG_DWORD', '/d', '0', '/f')
Run-Reg @('add', 'HKLM\PIPA_SOFTWARE\Policies\Microsoft\Windows\OOBE', '/v', 'DisablePrivacyExperience', '/t', 'REG_DWORD', '/d', '1', '/f')

Run-Reg @('query', 'HKLM\PIPA_SYSTEM\ControlSet001\Control\USB', '/v', 'OsDefaultRoleSwitchMode')
Run-Reg @('query', 'HKLM\PIPA_SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE', '/v', 'DefaultAccountAction')
Run-Reg @('query', 'HKLM\PIPA_SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE', '/v', 'LaunchUserOOBE')
Run-Reg @('query', 'HKLM\PIPA_SOFTWARE\Policies\Microsoft\Windows\OOBE', '/v', 'DisablePrivacyExperience')

Run-Reg @('unload', 'HKLM\PIPA_SYSTEM')
Run-Reg @('unload', 'HKLM\PIPA_SOFTWARE')

Log 'DONE'
"=== PIPA OFFLINE REGISTRY FIX END $(Get-Date -Format o) ===" | Add-Content -LiteralPath $LogPath

