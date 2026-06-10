param(
    [string] $CheckpointRoot = '<ARTIFACT_DIR>\checkpoints\stable-goffath-20260604',
    [string] $ImagePath = '<ARTIFACT_DIR>\checkpoints\pipa-win11-stable-goffath-20260604.wim',
    [string] $LogPath = '<ARTIFACT_DIR>\checkpoint-stable-goffath-20260604.log'
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
    param([string] $File, [string[]] $Arguments, [switch] $Robocopy)
    Log ("RUN {0} {1}" -f $File, ($Arguments -join ' '))
    & $File @Arguments 2>&1 | Tee-Object -FilePath $LogPath -Append
    $code = $LASTEXITCODE
    if ($Robocopy) {
        if ($code -gt 7) {
            throw "$File failed with exit $code"
        }
    } elseif ($code -ne 0) {
        throw "$File failed with exit $code"
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

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath), $CheckpointRoot | Out-Null
"=== PIPA STABLE WINDOWS CHECKPOINT START $(Get-Date -Format o) ===" |
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
if ($disk.IsOffline) {
    Set-Disk -Number $disk.Number -IsOffline $false
    Start-Sleep -Seconds 2
    Update-HostStorageCache
}

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
if (-not (Test-Path -LiteralPath 'W:\Windows\System32\winload.efi')) {
    throw 'Windows installation is missing winload.efi.'
}

Run chkdsk.exe @('W:', '/scan')
Run chkdsk.exe @('Z:', '/scan')

$manifest = [ordered]@{
    CapturedAt = (Get-Date -Format o)
    Device = 'Xiaomi Pad 6 pipa'
    WindowsPartition = 36
    EspPartition = 35
    AndroidPartitionUntouched = 34
    WindowsLabel = (Get-Volume -DriveLetter $WindowsLetter).FileSystemLabel
    WindowsSize = $windows.Size
    WindowsFree = (Get-Volume -DriveLetter $WindowsLetter).SizeRemaining
    ProfileVerifiedByUser = '<WINDOWS_USER_PROFILE>'
    StableUefi = '<ARTIFACT_DIR>\pipa_muold_touchmin_v8.img'
    StableUefiSha256 = (Get-FileHash -LiteralPath '<ARTIFACT_DIR>\pipa_muold_touchmin_v8.img' -Algorithm SHA256).Hash
}
$manifest | ConvertTo-Json |
    Set-Content -LiteralPath (Join-Path $CheckpointRoot 'manifest.json') -Encoding UTF8

Run robocopy.exe @('Z:\', (Join-Path $CheckpointRoot 'ESP'), '/E', '/R:1', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS', '/NP') -Robocopy

$critical = Join-Path $CheckpointRoot 'critical'
New-Item -ItemType Directory -Force -Path $critical | Out-Null
Copy-Item -LiteralPath 'W:\Windows\System32\config\SYSTEM' -Destination $critical -Force
Copy-Item -LiteralPath 'W:\Windows\System32\config\SOFTWARE' -Destination $critical -Force
Copy-Item -LiteralPath 'W:\Windows\System32\config\SAM' -Destination $critical -Force

if (Test-Path -LiteralPath $ImagePath) {
    throw "Checkpoint image already exists: $ImagePath"
}
$scratch = Join-Path (Split-Path -Parent $ImagePath) 'scratch'
New-Item -ItemType Directory -Force -Path $scratch | Out-Null
Run dism.exe @(
    '/Capture-Image',
    "/ImageFile:$ImagePath",
    '/CaptureDir:W:\',
    '/Name:Pipa Win11 Stable Goffath 2026-06-04',
    '/Description:Fresh stable boot, Goffath profile normal, before further driver tests',
    '/Compress:max',
    '/CheckIntegrity',
    '/Verify',
    "/ScratchDir:$scratch"
)

$hashes = Get-FileHash -Algorithm SHA256 -LiteralPath @(
    $ImagePath,
    (Join-Path $CheckpointRoot 'ESP\EFI\Microsoft\Boot\BCD'),
    (Join-Path $CheckpointRoot 'critical\SYSTEM'),
    (Join-Path $CheckpointRoot 'critical\SOFTWARE'),
    (Join-Path $CheckpointRoot 'critical\SAM')
)
$hashes | Export-Csv -LiteralPath (Join-Path $CheckpointRoot 'SHA256.csv') -NoTypeInformation
$hashes | Format-Table -AutoSize | Out-String |
    Tee-Object -FilePath $LogPath -Append | Write-Host

Log 'CHECKPOINT_CAPTURE_DONE'
"=== PIPA STABLE WINDOWS CHECKPOINT END $(Get-Date -Format o) ===" |
    Add-Content -LiteralPath $LogPath

