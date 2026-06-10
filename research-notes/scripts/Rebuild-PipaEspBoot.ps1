param(
    [string] $BackupRoot = '<ARTIFACT_DIR>\esp-backup-before-rebuild-20260604',
    [string] $LogPath = '<ARTIFACT_DIR>\esp-rebuild-20260604.log'
)

$ErrorActionPreference = 'Stop'
$WindowsLetter = 'W'
$EspLetter = 'Z'

function Log {
    param([string] $Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $line | Tee-Object -FilePath $LogPath -Append
}

function Ensure-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Administrator token required.'
    }
}

function Set-TargetLetter {
    param(
        [uint32] $DiskNumber,
        [uint32] $PartitionNumber,
        [char] $Letter
    )
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

Ensure-Admin
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath) | Out-Null
"=== PIPA ESP REBUILD START $(Get-Date -Format o) ===" |
    Set-Content -LiteralPath $LogPath -Encoding UTF8

Log 'Refreshing Windows storage cache for the USB mass-storage gadget'
Update-HostStorageCache
$diskpartScript = Join-Path $env:TEMP 'pipa-storage-rescan.txt'
Set-Content -LiteralPath $diskpartScript -Value "rescan`r`nexit`r`n" -Encoding ASCII
& diskpart.exe /s $diskpartScript 2>&1 | Tee-Object -FilePath $LogPath -Append
Start-Sleep -Seconds 5

$candidates = @(Get-Disk | Where-Object {
    $_.BusType -eq 'USB' -and
    $_.FriendlyName -eq 'Linux File-Stor Gadget' -and
    $_.PartitionStyle -eq 'GPT' -and
    $_.Size -gt 200GB -and
    $_.Size -lt 300GB
})
if ($candidates.Count -ne 1) {
    throw "Expected one Xiaomi USB GPT disk; found $($candidates.Count)."
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
Log "Verified target disk $($disk.Number). Partition 34 will not be touched."

Set-TargetLetter -DiskNumber $disk.Number -PartitionNumber 35 -Letter $EspLetter
Set-TargetLetter -DiskNumber $disk.Number -PartitionNumber 36 -Letter $WindowsLetter

if ((Get-Volume -DriveLetter $WindowsLetter).FileSystemLabel -ne 'WINPIPA') {
    throw 'W: is not WINPIPA.'
}
if ((Get-Volume -DriveLetter $EspLetter).FileSystem -ne 'FAT32') {
    throw 'Z: is not FAT32 ESP.'
}
if (-not (Test-Path -LiteralPath 'W:\Windows\System32\winload.efi')) {
    throw 'Windows installation is missing winload.efi.'
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $BackupRoot $stamp
New-Item -ItemType Directory -Force -Path $backup | Out-Null
Log "Backing up ESP to $backup"
& robocopy.exe 'Z:\' $backup /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP |
    Tee-Object -FilePath $LogPath -Append
if ($LASTEXITCODE -gt 7) {
    throw "ESP backup robocopy failed with exit $LASTEXITCODE."
}

Log 'Rebuilding Microsoft UEFI boot files and BCD from W:\Windows'
& bcdboot.exe 'W:\Windows' /s Z: /f UEFI /v 2>&1 |
    Tee-Object -FilePath $LogPath -Append
if ($LASTEXITCODE -ne 0) {
    throw "bcdboot failed with exit $LASTEXITCODE."
}

foreach ($args in @(
    @('/store', 'Z:\EFI\Microsoft\Boot\BCD', '/set', '{default}', 'testsigning', 'on'),
    @('/store', 'Z:\EFI\Microsoft\Boot\BCD', '/set', '{default}', 'recoveryenabled', 'yes'),
    @('/store', 'Z:\EFI\Microsoft\Boot\BCD', '/set', '{default}', 'bootlog', 'yes'),
    @('/store', 'Z:\EFI\Microsoft\Boot\BCD', '/set', '{bootmgr}', 'displaybootmenu', 'yes'),
    @('/store', 'Z:\EFI\Microsoft\Boot\BCD', '/timeout', '5')
)) {
    & bcdedit.exe @args 2>&1 | Tee-Object -FilePath $LogPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "bcdedit failed: $($args -join ' ')"
    }
}

Copy-Item -LiteralPath 'Z:\EFI\Microsoft\Boot\bootmgfw.efi' -Destination 'Z:\EFI\Boot\bootaa64.efi' -Force

Get-FileHash -Algorithm SHA256 -LiteralPath @(
    'Z:\EFI\Boot\bootaa64.efi',
    'Z:\EFI\Microsoft\Boot\bootmgfw.efi',
    'Z:\EFI\Microsoft\Boot\BCD',
    'W:\Windows\Boot\EFI\bootmgfw.efi',
    'W:\Windows\System32\winload.efi'
) | Format-Table -AutoSize | Out-String |
    Tee-Object -FilePath $LogPath -Append | Write-Host

Log 'ESP_REBUILD_DONE'
"=== PIPA ESP REBUILD END $(Get-Date -Format o) ===" |
    Add-Content -LiteralPath $LogPath

