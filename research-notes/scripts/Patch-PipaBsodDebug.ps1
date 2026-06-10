param(
    [string] $LogPath = '<ARTIFACT_DIR>\patch-bsod-debug-20260601.log',
    [switch] $EnableSafeMode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    "=== PIPA BSOD DEBUG PATCH START $(Get-Date -Format o) ===" | Set-Content -LiteralPath $LogPath -Encoding UTF8

function Log([string]$Message) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $line | Tee-Object -FilePath $LogPath -Append
}

function Run-Native([string]$Exe, [string[]]$ArgumentList, [switch]$AllowFailure) {
    Log ("RUN $Exe " + ($ArgumentList -join ' '))
    $output = & $Exe @ArgumentList 2>&1
    $exit = $LASTEXITCODE
    $output | Tee-Object -FilePath $LogPath -Append
    if (($exit -ne 0) -and (-not $AllowFailure)) {
        throw "$Exe failed with exit code $exit"
    }
}

function Ensure-DriveLetters {
    Log 'Assigning drive letters to pipa ESP/windows partitions if needed'
    $disk = Get-Disk | Where-Object {
        $_.BusType -eq 'USB' -and $_.PartitionStyle -eq 'GPT' -and
        ($_.FriendlyName -match 'Linux File-Stor|File-Stor|Mass Storage|Gadget')
    } | Sort-Object Number | Select-Object -First 1
    if (-not $disk) {
        throw 'Xiaomi mass-storage disk not found. Run TWRP msc.sh first.'
    }
    Log "Target disk number $($disk.Number), size $($disk.Size)"

    $esp = Get-Partition -DiskNumber $disk.Number -PartitionNumber 35 -ErrorAction Stop
    $win = Get-Partition -DiskNumber $disk.Number -PartitionNumber 36 -ErrorAction Stop
    if ($esp.Size -lt 500MB -or $esp.Size -gt 600MB) { throw "Unexpected ESP size: $($esp.Size)" }
    if ($win.Size -lt 40GB) { throw "Unexpected Windows partition size: $($win.Size)" }

    if ($esp.DriveLetter -ne 'Y') {
        if (Get-Volume -DriveLetter Y -ErrorAction SilentlyContinue) { throw 'Drive Y: is already in use' }
        Set-Partition -DiskNumber $disk.Number -PartitionNumber 35 -NewDriveLetter Y
    }
    if ($win.DriveLetter -ne 'E') {
        if (Get-Volume -DriveLetter E -ErrorAction SilentlyContinue) { throw 'Drive E: is already in use' }
        Set-Partition -DiskNumber $disk.Number -PartitionNumber 36 -NewDriveLetter E
    }
}

function Ensure-HiveLoaded([string]$Name, [string]$HivePath) {
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & reg.exe query "HKLM\$Name" *> $null
    $queryExit = $LASTEXITCODE
    $ErrorActionPreference = $oldPreference
    if ($queryExit -eq 0) {
        Log "$Name already loaded"
        return
    }
    Run-Native reg.exe @('load', "HKLM\$Name", $HivePath)
}

Ensure-DriveLetters

Log 'Patching offline Windows crash behavior'
Ensure-HiveLoaded 'PIPA_SYSTEM' 'E:\Windows\System32\Config\SYSTEM'
try {
    Run-Native reg.exe @('add', 'HKLM\PIPA_SYSTEM\ControlSet001\Control\CrashControl', '/v', 'AutoReboot', '/t', 'REG_DWORD', '/d', '0', '/f')
    Run-Native reg.exe @('add', 'HKLM\PIPA_SYSTEM\ControlSet001\Control\CrashControl', '/v', 'DisplayParameters', '/t', 'REG_DWORD', '/d', '1', '/f')
    Run-Native reg.exe @('add', 'HKLM\PIPA_SYSTEM\ControlSet001\Control\USB', '/v', 'OsDefaultRoleSwitchMode', '/t', 'REG_DWORD', '/d', '1', '/f')
    Run-Native reg.exe @('query', 'HKLM\PIPA_SYSTEM\ControlSet001\Control\CrashControl', '/v', 'AutoReboot')
    Run-Native reg.exe @('query', 'HKLM\PIPA_SYSTEM\ControlSet001\Control\USB', '/v', 'OsDefaultRoleSwitchMode')
}
finally {
    Run-Native reg.exe @('unload', 'HKLM\PIPA_SYSTEM') -AllowFailure
}

Log 'Patching offline BCD for visible boot/bugcheck diagnostics'
$store = 'Y:\EFI\Microsoft\Boot\BCD'
Run-Native bcdedit.exe @('/store', $store, '/set', '{default}', 'testsigning', 'on')
Run-Native bcdedit.exe @('/store', $store, '/set', '{default}', 'nointegritychecks', 'on') -AllowFailure
Run-Native bcdedit.exe @('/store', $store, '/set', '{default}', 'recoveryenabled', 'No')
Run-Native bcdedit.exe @('/store', $store, '/set', '{default}', 'bootstatuspolicy', 'IgnoreAllFailures')
Run-Native bcdedit.exe @('/store', $store, '/set', '{default}', 'bootlog', 'Yes')
Run-Native bcdedit.exe @('/store', $store, '/set', '{default}', 'sos', 'Yes')
Run-Native bcdedit.exe @('/store', $store, '/set', '{default}', 'bootux', 'disabled') -AllowFailure
Run-Native bcdedit.exe @('/store', $store, '/set', '{bootmgr}', 'displaybootmenu', 'Yes') -AllowFailure
Run-Native bcdedit.exe @('/store', $store, '/timeout', '10') -AllowFailure

if ($EnableSafeMode) {
    Log 'Enabling Safe Mode minimal in offline BCD'
    Run-Native bcdedit.exe @('/store', $store, '/set', '{default}', 'safeboot', 'minimal')
}
else {
    Run-Native bcdedit.exe @('/store', $store, '/deletevalue', '{default}', 'safeboot') -AllowFailure
}

Log 'BCD summary'
Run-Native bcdedit.exe @('/store', $store, '/enum', '{default}') -AllowFailure

Log 'DONE'
"=== PIPA BSOD DEBUG PATCH END $(Get-Date -Format o) ===" | Add-Content -LiteralPath $LogPath
}
catch {
    try {
        "[{0}] ERROR {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $_.Exception.Message |
            Add-Content -LiteralPath $LogPath
        if ($_.ScriptStackTrace) {
            $_.ScriptStackTrace | Add-Content -LiteralPath $LogPath
        }
    }
    catch {}
    throw
}

