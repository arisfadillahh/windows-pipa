param(
    [string[]] $Services = @('qcPILC'),
    [string] $LogPath = '<ARTIFACT_DIR>\patch-disable-windows-services-20260601.log'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    "=== PIPA DISABLE WINDOWS SERVICES START $(Get-Date -Format o) ===" | Set-Content -LiteralPath $LogPath -Encoding UTF8

function Log([string]$Message) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $line | Tee-Object -FilePath $LogPath -Append | Out-Null
}

function Run-Native([string]$Exe, [string[]]$ArgumentList, [switch]$AllowFailure) {
    Log ("RUN $Exe " + ($ArgumentList -join ' '))
    $oldPreference = $ErrorActionPreference
    if ($AllowFailure) {
        $ErrorActionPreference = 'Continue'
    }
    $output = & $Exe @ArgumentList 2>&1
    $exit = $LASTEXITCODE
    $ErrorActionPreference = $oldPreference
    $output | Tee-Object -FilePath $LogPath -Append | Out-Null
    if (($exit -ne 0) -and (-not $AllowFailure)) {
        throw "$Exe failed with exit code $exit"
    }
    return $exit
}

    $disk = Get-Disk | Where-Object {
        $_.BusType -eq 'USB' -and $_.PartitionStyle -eq 'GPT' -and
        ($_.FriendlyName -match 'Linux File-Stor|File-Stor|Mass Storage|Gadget')
    } | Sort-Object Number | Select-Object -First 1
    if (-not $disk) { throw 'Xiaomi mass-storage disk not found. Run TWRP msc.sh first.' }
    Log "Target disk number $($disk.Number), size $($disk.Size)"

    $win = Get-Partition -DiskNumber $disk.Number -PartitionNumber 36 -ErrorAction Stop
    if ($win.DriveLetter -ne 'E') {
        if (Get-Volume -DriveLetter E -ErrorAction SilentlyContinue) { throw 'Drive E: is already in use' }
        Set-Partition -DiskNumber $disk.Number -PartitionNumber 36 -NewDriveLetter E
    }

    Run-Native reg.exe @('load', 'HKLM\PIPA_SYSTEM', 'E:\Windows\System32\Config\SYSTEM')
    try {
        foreach ($controlSet in @('ControlSet001', 'ControlSet002')) {
            foreach ($service in $Services) {
                $key = "HKLM\PIPA_SYSTEM\$controlSet\Services\$service"
                $exists = Run-Native reg.exe @('query', $key) -AllowFailure
                if ($exists -eq 0) {
                    Run-Native reg.exe @('query', $key, '/v', 'Start') -AllowFailure | Out-Null
                    Run-Native reg.exe @('add', $key, '/v', 'Start', '/t', 'REG_DWORD', '/d', '4', '/f') | Out-Null
                    Run-Native reg.exe @('query', $key, '/v', 'Start') -AllowFailure | Out-Null
                }
                else {
                    Log "SKIP missing $key"
                }
            }
        }
    }
    finally {
        Run-Native reg.exe @('unload', 'HKLM\PIPA_SYSTEM') -AllowFailure
    }

    Log 'DONE'
    "=== PIPA DISABLE WINDOWS SERVICES END $(Get-Date -Format o) ===" | Add-Content -LiteralPath $LogPath
}
catch {
    try {
        "[{0}] ERROR {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $_.Exception.Message |
            Add-Content -LiteralPath $LogPath
        if ($_.ScriptStackTrace) { $_.ScriptStackTrace | Add-Content -LiteralPath $LogPath }
    }
    catch {}
    throw
}

