param(
    [string] $WinDrive = 'E',
    [string] $ProjectRoot = '<PROJECT_ROOT>',
    [string] $WorkspaceRoot = '<WORKSPACE>',
    [string] $LogPath = '<ARTIFACT_DIR>\stage-qcspi-only-letter-20260605.log'
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
    $argList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', "`"$PSCommandPath`"",
        '-WinDrive', $WinDrive,
        '-ProjectRoot', "`"$ProjectRoot`"",
        '-WorkspaceRoot', "`"$WorkspaceRoot`"",
        '-LogPath', "`"$LogPath`""
    ) -join ' '
    Start-Process powershell.exe -Verb RunAs -ArgumentList $argList -Wait
    exit
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath) | Out-Null
"=== PIPA QCSPI-ONLY LETTER STAGE START $(Get-Date -Format o) ===" |
    Set-Content -LiteralPath $LogPath -Encoding UTF8

$driveRoot = "$($WinDrive.TrimEnd(':')):\"
$volume = Get-Volume -DriveLetter $WinDrive.TrimEnd(':')
if ($volume.FileSystemLabel -ne 'WINPIPA' -or $volume.FileSystem -ne 'NTFS') {
    throw "$driveRoot is not WINPIPA NTFS."
}
if ($volume.Size -lt 60GB -or $volume.Size -gt 75GB) {
    throw "$driveRoot size safety check failed: $($volume.Size)."
}
if (-not (Test-Path -LiteralPath (Join-Path $driveRoot 'Windows\System32\config\SYSTEM'))) {
    throw "$driveRoot does not look like the pipa Windows volume."
}
Log "Verified $driveRoot as WINPIPA. Android userdata is not exposed to this script."

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

$targetRoot = Join-Path $driveRoot 'woa\qcspi-only'
$targetDriver = Join-Path $targetRoot 'driver'
$backup = Join-Path $targetRoot 'pre-test-backup'
$startupDir = Join-Path $driveRoot 'ProgramData\Microsoft\Windows\Start Menu\Programs\Startup'
$startupTarget = Join-Path $startupDir 'Codex-QCSPI-Only.cmd'
New-Item -ItemType Directory -Force -Path $targetDriver, $backup, $startupDir | Out-Null

Remove-Item -LiteralPath (Join-Path $targetDriver 'qcspi8250-pipa.inf') -Force -ErrorAction SilentlyContinue
Copy-Item -LiteralPath (Join-Path $sourceDriver 'qcspi8250.inf') -Destination $targetDriver -Force
Copy-Item -LiteralPath (Join-Path $sourceDriver 'qcspi8250.cat') -Destination $targetDriver -Force
Copy-Item -LiteralPath (Join-Path $sourceDriver 'qcspi8250.sys') -Destination $targetDriver -Force
Copy-Item -LiteralPath $sourceScript -Destination $targetRoot -Force
Copy-Item -LiteralPath $sourceCmd -Destination $targetRoot -Force
Copy-Item -LiteralPath $sourceCmd -Destination $startupTarget -Force
Copy-Item -LiteralPath (Join-Path $driveRoot 'Windows\System32\config\SOFTWARE') -Destination $backup -Force
Copy-Item -LiteralPath (Join-Path $driveRoot 'Windows\System32\config\SYSTEM') -Destination $backup -Force
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
"=== PIPA QCSPI-ONLY LETTER STAGE END $(Get-Date -Format o) ===" |
    Add-Content -LiteralPath $LogPath

