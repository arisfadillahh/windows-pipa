param(
    [string] $CheckpointRoot = '<ARTIFACT_DIR>\checkpoints\stable-goffath-20260604',
    [string] $LogPath = '<ARTIFACT_DIR>\checkpoint-stable-goffath-lite-20260604.log'
)

$ErrorActionPreference = 'Stop'

function Log {
    param([string] $Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $line | Tee-Object -FilePath $LogPath -Append
}

function Copy-Tree {
    param(
        [string] $Source,
        [string] $Destination,
        [string[]] $ExtraArguments = @()
    )
    Log "COPY $Source -> $Destination"
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $arguments = @(
        $Source, $Destination,
        '/E', '/COPY:DAT', '/DCOPY:DAT', '/XJ', '/XJF', '/XJD',
        '/R:1', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS', '/NP'
    ) + $ExtraArguments
    & robocopy.exe @arguments 2>&1 |
        Tee-Object -FilePath $LogPath -Append
    if ($LASTEXITCODE -gt 7) {
        throw "robocopy failed with exit $LASTEXITCODE for $Source"
    }
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Administrator token required.'
}

New-Item -ItemType Directory -Force -Path $CheckpointRoot | Out-Null
"=== PIPA STABLE LITE CHECKPOINT START $(Get-Date -Format o) ===" |
    Set-Content -LiteralPath $LogPath -Encoding UTF8

Update-HostStorageCache
$disk = @(Get-Disk | Where-Object {
    $_.BusType -eq 'USB' -and
    $_.FriendlyName -eq 'Linux File-Stor Gadget' -and
    $_.PartitionStyle -eq 'GPT' -and
    $_.Size -gt 200GB -and
    $_.Size -lt 300GB
})
if ($disk.Count -ne 1) {
    throw "Expected exactly one Xiaomi USB GPT target; found $($disk.Count)."
}
$disk = $disk[0]
if ($disk.IsOffline) {
    Set-Disk -Number $disk.Number -IsOffline $false
    Start-Sleep -Seconds 2
    Update-HostStorageCache
}

$userdata = Get-Partition -DiskNumber $disk.Number -PartitionNumber 34
$esp = Get-Partition -DiskNumber $disk.Number -PartitionNumber 35
$windows = Get-Partition -DiskNumber $disk.Number -PartitionNumber 36
if ($userdata.Size -lt 100GB -or $userdata.Size -gt 150GB) {
    throw 'Android userdata safety check failed.'
}
if ($esp.Size -lt 400MB -or $esp.Size -gt 700MB -or
    $esp.GptType -ne '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}') {
    throw 'ESP safety check failed.'
}
if ($windows.Size -lt 60GB -or $windows.Size -gt 75GB -or
    $windows.GptType -ne '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}') {
    throw 'Windows partition safety check failed.'
}
Log "Verified disk $($disk.Number). Android partition 34 will not be touched."

$espPart = Get-Partition -DiskNumber $disk.Number -PartitionNumber 35
$winPart = Get-Partition -DiskNumber $disk.Number -PartitionNumber 36
if ($espPart.DriveLetter -ne 'Z') {
    Set-Partition -DiskNumber $disk.Number -PartitionNumber 35 -NewDriveLetter Z
}
if ($winPart.DriveLetter -ne 'W') {
    Set-Partition -DiskNumber $disk.Number -PartitionNumber 36 -NewDriveLetter W
}
if ((Get-Volume -DriveLetter W).FileSystemLabel -ne 'WINPIPA') {
    throw 'W: is not WINPIPA.'
}

$partialWim = '<ARTIFACT_DIR>\checkpoints\pipa-win11-stable-goffath-20260604.wim'
if (Test-Path -LiteralPath $partialWim) {
    $item = Get-Item -LiteralPath $partialWim
    if ($item.Length -lt 1MB) {
        Remove-Item -LiteralPath $partialWim -Force
        Log "Removed invalid partial WIM ($($item.Length) bytes)."
    }
}

Copy-Tree 'Z:\' (Join-Path $CheckpointRoot 'ESP')
Copy-Tree 'W:\Windows\System32\config' (Join-Path $CheckpointRoot 'Windows-System32-config') @('/LEV:1')
Copy-Tree 'W:\Windows\System32\DriverStore\FileRepository' (Join-Path $CheckpointRoot 'DriverStore-FileRepository')
Copy-Tree 'W:\Windows\System32\drivers' (Join-Path $CheckpointRoot 'Windows-System32-drivers')
Copy-Tree 'W:\Windows\INF' (Join-Path $CheckpointRoot 'Windows-INF')
if (Test-Path -LiteralPath 'W:\Users\Goffath') {
    Copy-Tree 'W:\Users\Goffath' (Join-Path $CheckpointRoot 'Users-Goffath') @(
        '/XD',
        'W:\Users\Goffath\AppData\Local\Microsoft\WindowsApps'
    )
}

$files = Get-ChildItem -LiteralPath $CheckpointRoot -Recurse -File
$summary = [ordered]@{
    CompletedAt = (Get-Date -Format o)
    Device = 'Xiaomi Pad 6 pipa'
    ProfileVerified = '<WINDOWS_USER_PROFILE>'
    AndroidPartitionUntouched = 34
    EspPartition = 35
    WindowsPartition = 36
    FileCount = $files.Count
    TotalBytes = ($files | Measure-Object Length -Sum).Sum
    StableUefi = '<ARTIFACT_DIR>\pipa_muold_touchmin_v8.img'
    StableUefiSha256 = (Get-FileHash -LiteralPath '<ARTIFACT_DIR>\pipa_muold_touchmin_v8.img' -Algorithm SHA256).Hash
    FullWimCapture = 'Skipped after PC interruption; lite rollback contains ESP, registry, DriverStore, active drivers, INF, and Goffath profile.'
}
$summary | ConvertTo-Json |
    Set-Content -LiteralPath (Join-Path $CheckpointRoot 'lite-checkpoint-summary.json') -Encoding UTF8

Get-FileHash -Algorithm SHA256 -LiteralPath @(
    (Join-Path $CheckpointRoot 'ESP\EFI\Microsoft\Boot\BCD'),
    (Join-Path $CheckpointRoot 'Windows-System32-config\SYSTEM'),
    (Join-Path $CheckpointRoot 'Windows-System32-config\SOFTWARE'),
    (Join-Path $CheckpointRoot 'Windows-System32-config\SAM')
) | Export-Csv -LiteralPath (Join-Path $CheckpointRoot 'lite-critical-SHA256.csv') -NoTypeInformation

Log "CHECKPOINT_LITE_DONE files=$($summary.FileCount) bytes=$($summary.TotalBytes)"
"=== PIPA STABLE LITE CHECKPOINT END $(Get-Date -Format o) ===" |
    Add-Content -LiteralPath $LogPath

