param(
    [string] $LogPath = '<ARTIFACT_DIR>\finalize-qcgpi-autorun-20260604.log'
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
"=== PIPA QCGPI AUTORUN FINALIZE START $(Get-Date -Format o) ===" |
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
$userdata = Get-Partition -DiskNumber $disk.Number -PartitionNumber 34
$windows = Get-Partition -DiskNumber $disk.Number -PartitionNumber 36
if ($userdata.Size -lt 100GB -or $userdata.Size -gt 150GB) {
    throw 'Android userdata safety check failed.'
}
if ($windows.Size -lt 60GB -or $windows.Size -gt 75GB -or
    $windows.GptType -ne '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}') {
    throw 'Windows partition safety check failed.'
}
Log "Verified disk $($disk.Number). Android partition 34 will not be touched."

if ((Get-Partition -DiskNumber $disk.Number -PartitionNumber 36).DriveLetter -ne 'W') {
    Set-Partition -DiskNumber $disk.Number -PartitionNumber 36 -NewDriveLetter W
}
if ((Get-Volume -DriveLetter W).FileSystemLabel -ne 'WINPIPA') {
    throw 'W: is not WINPIPA.'
}

$root = 'W:\woa\qcgpi-only'
$payload = @(
    (Join-Path $root 'Test-PipaQcgpiOnly.ps1'),
    (Join-Path $root 'Run-PipaQcgpiOnly.cmd'),
    (Join-Path $root 'woa-kmci-leaf.cer'),
    (Join-Path $root 'driver\qcgpi8150.inf'),
    (Join-Path $root 'driver\qcgpi8150.sys'),
    (Join-Path $root 'driver\qcgpi8150.cat')
)
foreach ($path in $payload) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing staged payload: $path"
    }
}

$startup = 'W:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup'
New-Item -ItemType Directory -Force -Path $startup | Out-Null
Copy-Item -LiteralPath (Join-Path $root 'Run-PipaQcgpiOnly.cmd') `
    -Destination (Join-Path $startup 'Codex-QCGPI-Only.cmd') -Force
Log 'Installed Startup fallback.'

$hive = 'HKLM\PIPA_QCGPI_SOFTWARE'
& reg.exe unload $hive 2>$null | Out-Null
& reg.exe load $hive 'W:\Windows\System32\config\SOFTWARE' 2>&1 |
    Tee-Object -FilePath $LogPath -Append
if ($LASTEXITCODE -ne 0) {
    throw "reg load failed with exit $LASTEXITCODE"
}
try {
    $command = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\woa\qcgpi-only\Test-PipaQcgpiOnly.ps1'
    & reg.exe add "$hive\Microsoft\Windows\CurrentVersion\RunOnce" /v CodexQcgpiOnly /t REG_SZ /d $command /f 2>&1 |
        Tee-Object -FilePath $LogPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "reg add failed with exit $LASTEXITCODE"
    }
    & reg.exe query "$hive\Microsoft\Windows\CurrentVersion\RunOnce" /v CodexQcgpiOnly 2>&1 |
        Tee-Object -FilePath $LogPath -Append
} finally {
    & reg.exe unload $hive 2>&1 | Tee-Object -FilePath $LogPath -Append
}

Log 'QCGPI_AUTORUN_FINALIZE_DONE'
"=== PIPA QCGPI AUTORUN FINALIZE END $(Get-Date -Format o) ===" |
    Add-Content -LiteralPath $LogPath

