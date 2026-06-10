param(
    [string] $WinDrive = 'F',
    [string] $LogPath = '<ARTIFACT_DIR>\disable-qcspi-offline-20260605.log'
)

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $argList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', "`"$PSCommandPath`"",
        '-WinDrive', $WinDrive,
        '-LogPath', "`"$LogPath`""
    ) -join ' '
    Start-Process powershell.exe -Verb RunAs -ArgumentList $argList -Wait
    exit
}

function Log {
    param([string] $Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $line | Tee-Object -FilePath $LogPath -Append
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath) | Out-Null
"=== PIPA QCSPI OFFLINE DISABLE START $(Get-Date -Format o) ===" |
    Set-Content -LiteralPath $LogPath -Encoding UTF8

$driveRoot = "$($WinDrive.TrimEnd(':')):\"
$volume = Get-Volume -DriveLetter $WinDrive.TrimEnd(':')
if ($volume.FileSystemLabel -ne 'WINPIPA' -or $volume.FileSystem -ne 'NTFS') {
    throw "$driveRoot is not WINPIPA NTFS."
}
if ($volume.Size -lt 60GB -or $volume.Size -gt 75GB) {
    throw "$driveRoot size safety check failed: $($volume.Size)."
}
Log "Verified $driveRoot as WINPIPA."

$testRoots = @(
    @{ Root = (Join-Path $driveRoot 'woa\qcspi-only'); Startup = 'Codex-QCSPI-Only.cmd' },
    @{ Root = (Join-Path $driveRoot 'woa\pad5-spi-only'); Startup = 'Codex-Pad5-SPI-Only.cmd' }
)
foreach ($test in $testRoots) {
    $root = $test.Root
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    "STOPPED_BY_CODEX_OFFLINE $(Get-Date -Format o)" |
        Set-Content -LiteralPath (Join-Path $root 'DONE.txt') -Encoding ASCII
    "QCSPI disabled offline after reboot loop." |
        Set-Content -LiteralPath (Join-Path $root 'DISABLED-BY-CODEX.txt') -Encoding UTF8

    $startup = Join-Path $driveRoot "ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\$($test.Startup)"
    if (Test-Path -LiteralPath $startup) {
        Move-Item -LiteralPath $startup -Destination (Join-Path $root "$($test.Startup).disabled") -Force
        Log "Removed Startup fallback: $($test.Startup)"
    } else {
        Log "Startup fallback already absent: $($test.Startup)"
    }
}

$infDir = Join-Path $driveRoot 'Windows\INF'
$candidateInfs = @(Get-ChildItem -LiteralPath $infDir -Filter 'oem*.inf' -ErrorAction SilentlyContinue |
    Where-Object {
        $text = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue
        $text -match 'qcspi|QCOM250F|QCOM050F'
    })

foreach ($inf in $candidateInfs) {
    Log "Removing offline driver package $($inf.Name)"
    & dism.exe /Image:$driveRoot /Remove-Driver /Driver:$($inf.Name) /LogPath:$LogPath 2>&1 |
        Tee-Object -FilePath $LogPath -Append
}
if ($candidateInfs.Count -eq 0) {
    Log 'No qcspi-like oem INF found.'
}

$hive = 'HKLM\PIPA_OFF_SYSTEM'
$systemHive = Join-Path $driveRoot 'Windows\System32\config\SYSTEM'
$loaded = $false
try {
    & reg.exe load $hive $systemHive 2>&1 | Tee-Object -FilePath $LogPath -Append
    $loaded = $true
    foreach ($path in @(
        "$hive\ControlSet001\Services\qcspi",
        "$hive\ControlSet002\Services\qcspi",
        "$hive\CurrentControlSet\Services\qcspi"
    )) {
        $exists = & reg.exe query $path 2>$null
        if ($LASTEXITCODE -eq 0) {
            Log "Disabling service key $path"
            & reg.exe add $path /v Start /t REG_DWORD /d 4 /f 2>&1 |
                Tee-Object -FilePath $LogPath -Append
        }
    }
} finally {
    if ($loaded) {
        [gc]::Collect()
        Start-Sleep -Milliseconds 500
        & reg.exe unload $hive 2>&1 | Tee-Object -FilePath $LogPath -Append
    }
}

Log 'QCSPI_OFFLINE_DISABLE_DONE'
"=== PIPA QCSPI OFFLINE DISABLE END $(Get-Date -Format o) ===" |
    Add-Content -LiteralPath $LogPath

