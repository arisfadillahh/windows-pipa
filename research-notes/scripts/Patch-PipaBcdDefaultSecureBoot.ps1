param(
    [string] $LogPath = '<ARTIFACT_DIR>\patch-bcd-default-secureboot-20260601.log'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    "=== PIPA BCD DEFAULT PATCH START $(Get-Date -Format o) ===" | Set-Content -LiteralPath $LogPath -Encoding UTF8

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
    if ($esp.DriveLetter -ne 'Y') {
        if (Get-Volume -DriveLetter Y -ErrorAction SilentlyContinue) { throw 'Drive Y: is already in use' }
        Set-Partition -DiskNumber $disk.Number -PartitionNumber 35 -NewDriveLetter Y
    }
    if ($win.DriveLetter -ne 'E') {
        if (Get-Volume -DriveLetter E -ErrorAction SilentlyContinue) { throw 'Drive E: is already in use' }
        Set-Partition -DiskNumber $disk.Number -PartitionNumber 36 -NewDriveLetter E
    }

    $store = 'Y:\EFI\Microsoft\Boot\BCD'
    Log 'Removing BCD options that conflict with Secure Boot validation'
    foreach ($value in @(
        'testsigning',
        'nointegritychecks',
        'safeboot',
        'bootlog',
        'sos',
        'bootux',
        'bootstatuspolicy'
    )) {
        Run-Native bcdedit.exe @('/store', $store, '/deletevalue', '{default}', $value) -AllowFailure
    }

    Run-Native bcdedit.exe @('/store', $store, '/set', '{default}', 'recoveryenabled', 'No') -AllowFailure
    Run-Native bcdedit.exe @('/store', $store, '/set', '{bootmgr}', 'displaybootmenu', 'No') -AllowFailure
    Run-Native bcdedit.exe @('/store', $store, '/timeout', '0') -AllowFailure

    Log 'BCD summary'
    Run-Native bcdedit.exe @('/store', $store, '/enum', '{default}') -AllowFailure

    Log 'DONE'
    "=== PIPA BCD DEFAULT PATCH END $(Get-Date -Format o) ===" | Add-Content -LiteralPath $LogPath
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

