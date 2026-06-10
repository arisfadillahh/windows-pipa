param(
    [string] $ProjectRoot = '<PROJECT_ROOT>',
    [string] $WorkspaceRoot = '<WORKSPACE>',
    [string] $LogPath = '<ARTIFACT_DIR>\stage-qcspi-only-20260604.log'
)

$ErrorActionPreference = 'Stop'

function Log {
    param([string] $Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $line | Tee-Object -FilePath $LogPath -Append
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Administrator token required.'
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath) | Out-Null
"=== PIPA QCSPI-ONLY STAGE START $(Get-Date -Format o) ===" |
    Set-Content -LiteralPath $LogPath -Encoding UTF8

Update-HostStorageCache
$candidate = @(Get-Disk | Where-Object {
    $_.BusType -eq 'USB' -and
    $_.FriendlyName -eq 'Linux File-Stor Gadget' -and
    $_.PartitionStyle -eq 'GPT' -and
    $_.Size -gt 200GB -and
    $_.Size -lt 300GB
})
if ($candidate.Count -ne 1) {
    throw "Expected exactly one Xiaomi USB GPT target; found $($candidate.Count)."
}
$disk = $candidate[0]
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

$winPart = Get-Partition -DiskNumber $disk.Number -PartitionNumber 36
if ($winPart.DriveLetter -ne 'W') {
    Set-Partition -DiskNumber $disk.Number -PartitionNumber 36 -NewDriveLetter W
}
if ((Get-Volume -DriveLetter W).FileSystemLabel -ne 'WINPIPA') {
    throw 'W: is not WINPIPA.'
}

$sourceDriver = Join-Path $ProjectRoot 'kona-drivers\Drivers\SOC\SPI'
$sourceScript = Join-Path $WorkspaceRoot 'scripts\Test-PipaQcspiOnly.ps1'
$sourceCmd = Join-Path $WorkspaceRoot 'scripts\Run-PipaQcspiOnly.cmd'
foreach ($required in @(
    (Join-Path $sourceDriver 'qcspi8250.inf'),
    (Join-Path $sourceDriver 'qcspi8250.cat'),
    (Join-Path $sourceDriver 'qcspi8250.sys'),
    $sourceScript,
    $sourceCmd
)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required payload missing: $required"
    }
}

$targetRoot = 'W:\woa\qcspi-only'
$targetDriver = Join-Path $targetRoot 'driver'
$backup = Join-Path $targetRoot 'pre-test-backup'
$startupDir = 'W:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup'
$startupTarget = Join-Path $startupDir 'Codex-QCSPI-Only.cmd'
New-Item -ItemType Directory -Force -Path $targetDriver, $backup, $startupDir | Out-Null

Remove-Item -LiteralPath (Join-Path $targetDriver 'qcspi8250-pipa.inf') -Force -ErrorAction SilentlyContinue
Copy-Item -LiteralPath (Join-Path $sourceDriver 'qcspi8250.inf') -Destination $targetDriver -Force
Copy-Item -LiteralPath (Join-Path $sourceDriver 'qcspi8250.cat') -Destination $targetDriver -Force
Copy-Item -LiteralPath (Join-Path $sourceDriver 'qcspi8250.sys') -Destination $targetDriver -Force
Copy-Item -LiteralPath $sourceScript -Destination $targetRoot -Force
Copy-Item -LiteralPath $sourceCmd -Destination $targetRoot -Force
Copy-Item -LiteralPath $sourceCmd -Destination $startupTarget -Force
Copy-Item -LiteralPath 'W:\Windows\System32\config\SOFTWARE' -Destination $backup -Force
Copy-Item -LiteralPath 'W:\Windows\System32\config\SYSTEM' -Destination $backup -Force
Remove-Item -LiteralPath (Join-Path $targetRoot 'DONE.txt'), (Join-Path $targetRoot 'RESULT.txt'), (Join-Path $targetRoot 'ATTEMPTED.txt') `
    -Force -ErrorAction SilentlyContinue

$hashes = Get-FileHash -Algorithm SHA256 -LiteralPath @(
    (Join-Path $targetDriver 'qcspi8250.inf'),
    (Join-Path $targetDriver 'qcspi8250.cat'),
    (Join-Path $targetDriver 'qcspi8250.sys'),
    (Join-Path $targetRoot 'Test-PipaQcspiOnly.ps1'),
    $startupTarget
)
$hashes | Format-Table -AutoSize | Out-String |
    Tee-Object -FilePath $LogPath -Append | Write-Host

Log "Startup fallback installed: $startupTarget"
Log 'QCSPI_ONLY_STAGE_DONE'
"=== PIPA QCSPI-ONLY STAGE END $(Get-Date -Format o) ===" |
    Add-Content -LiteralPath $LogPath

