param(
    [string] $LogPath = '<ARTIFACT_DIR>\boot-repair-mass-storage-20260604.log',
    [string] $BackupRoot = '<ARTIFACT_DIR>\esp-backup-before-boot-repair-20260604'
)

$ErrorActionPreference = 'Stop'
$WindowsLetter = 'W'
$EspLetter = 'Z'

function Log {
    param([string] $Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $line | Tee-Object -FilePath $LogPath -Append
}

function Run {
    param([string] $File, [string[]] $Arguments)
    Log ("RUN {0} {1}" -f $File, ($Arguments -join ' '))
    & $File @Arguments 2>&1 | Tee-Object -FilePath $LogPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "$File failed with exit $LASTEXITCODE"
    }
}

function Set-TargetLetter {
    param([uint32] $DiskNumber, [uint32] $PartitionNumber, [char] $Letter)
    $occupied = Get-Partition -DriveLetter $Letter -ErrorAction SilentlyContinue
    if ($occupied -and (
        $occupied.DiskNumber -ne $DiskNumber -or
        $occupied.PartitionNumber -ne $PartitionNumber
    )) {
        throw "Drive letter $Letter is occupied by another partition."
    }
    $partition = Get-Partition -DiskNumber $DiskNumber -PartitionNumber $PartitionNumber
    if ($partition.DriveLetter -ne $Letter) {
        Set-Partition -DiskNumber $DiskNumber -PartitionNumber $PartitionNumber -NewDriveLetter $Letter
    }
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Administrator token required.'
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath) | Out-Null
"=== PIPA MASS-STORAGE BOOT REPAIR START $(Get-Date -Format o) ===" |
    Set-Content -LiteralPath $LogPath -Encoding UTF8

Update-HostStorageCache
$candidates = @(Get-Disk | Where-Object {
    $_.BusType -eq 'USB' -and
    $_.FriendlyName -eq 'Linux File-Stor Gadget' -and
    $_.PartitionStyle -eq 'GPT' -and
    $_.Size -gt 200GB -and
    $_.Size -lt 300GB
})
if ($candidates.Count -ne 1) {
    throw "Expected exactly one Xiaomi whole-disk USB GPT target; found $($candidates.Count)."
}

$disk = $candidates[0]
$userdata = Get-Partition -DiskNumber $disk.Number -PartitionNumber 34
$esp = Get-Partition -DiskNumber $disk.Number -PartitionNumber 35
$windows = Get-Partition -DiskNumber $disk.Number -PartitionNumber 36

if ($userdata.Size -lt 100GB -or $userdata.Size -gt 150GB) {
    throw 'Safety check failed for Android userdata partition 34.'
}
if ($esp.Size -lt 400MB -or $esp.Size -gt 700MB -or
    $esp.GptType -ne '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}') {
    throw 'Safety check failed for ESP partition 35.'
}
if ($windows.Size -lt 60GB -or $windows.Size -gt 75GB -or
    $windows.GptType -ne '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}') {
    throw 'Safety check failed for Windows partition 36.'
}
Log "Verified disk $($disk.Number). Android partition 34 will not be touched."

Set-TargetLetter -DiskNumber $disk.Number -PartitionNumber 35 -Letter $EspLetter
Set-TargetLetter -DiskNumber $disk.Number -PartitionNumber 36 -Letter $WindowsLetter

if ((Get-Volume -DriveLetter $WindowsLetter).FileSystemLabel -ne 'WINPIPA') {
    throw 'W: is not WINPIPA.'
}
if ((Get-Volume -DriveLetter $EspLetter).FileSystem -ne 'FAT32') {
    throw 'Z: is not FAT32 ESP.'
}

$backup = Join-Path $BackupRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
New-Item -ItemType Directory -Force -Path $backup | Out-Null
Log "Backing up ESP to $backup"
& robocopy.exe 'Z:\' $backup /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP |
    Tee-Object -FilePath $LogPath -Append
if ($LASTEXITCODE -gt 7) {
    throw "ESP backup failed with robocopy exit $LASTEXITCODE."
}

Run chkdsk.exe @('W:', '/scan')
Run chkdsk.exe @('Z:', '/scan')
Run bcdboot.exe @('W:\Windows', '/s', 'Z:', '/f', 'UEFI', '/v')
Run bcdedit.exe @('/store', 'Z:\EFI\Microsoft\Boot\BCD', '/set', '{default}', 'testsigning', 'on')
Run bcdedit.exe @('/store', 'Z:\EFI\Microsoft\Boot\BCD', '/set', '{default}', 'recoveryenabled', 'yes')
Run bcdedit.exe @('/store', 'Z:\EFI\Microsoft\Boot\BCD', '/set', '{default}', 'bootlog', 'yes')
Run bcdedit.exe @('/store', 'Z:\EFI\Microsoft\Boot\BCD', '/deletevalue', '{default}', 'resumeobject')
Copy-Item -LiteralPath 'Z:\EFI\Microsoft\Boot\bootmgfw.efi' -Destination 'Z:\EFI\Boot\bootaa64.efi' -Force

Get-FileHash -Algorithm SHA256 -LiteralPath @(
    'Z:\EFI\Boot\bootaa64.efi',
    'Z:\EFI\Microsoft\Boot\bootmgfw.efi',
    'Z:\EFI\Microsoft\Boot\BCD',
    'W:\Windows\Boot\EFI\bootmgfw.efi',
    'W:\Windows\System32\winload.efi'
) | Format-Table -AutoSize | Out-String |
    Tee-Object -FilePath $LogPath -Append | Write-Host

Log 'BOOT_REPAIR_DONE'
"=== PIPA MASS-STORAGE BOOT REPAIR END $(Get-Date -Format o) ===" |
    Add-Content -LiteralPath $LogPath

