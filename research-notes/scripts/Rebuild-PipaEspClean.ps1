param(
    [string] $LogPath = '<ARTIFACT_DIR>\esp-clean-rebuild-20260604.log',
    [string] $BackupRoot = '<ARTIFACT_DIR>\esp-backup-clean-rebuild-20260604'
)

$ErrorActionPreference = 'Stop'
$WindowsLetter = 'W'
$EspLetter = 'Z'

function Log {
    param([string] $Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $line | Tee-Object -FilePath $LogPath -Append
}

function Run-Process {
    param(
        [string] $File,
        [string[]] $Arguments,
        [int] $TimeoutSeconds = 90,
        [switch] $AllowFailure
    )

    $stdout = Join-Path $env:TEMP ("pipa-{0}-out.txt" -f [guid]::NewGuid())
    $stderr = Join-Path $env:TEMP ("pipa-{0}-err.txt" -f [guid]::NewGuid())
    Log ("RUN {0} {1}" -f $File, ($Arguments -join ' '))

    $quotedArguments = @($Arguments | ForEach-Object {
        if ($_ -match '\s') {
            '"' + $_.Replace('"', '\"') + '"'
        } else {
            $_
        }
    })
    $process = Start-Process -FilePath $File -ArgumentList $quotedArguments -Wait -PassThru `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $process.Refresh()
    $exitCode = $process.ExitCode

    foreach ($path in @($stdout, $stderr)) {
        if (Test-Path -LiteralPath $path) {
            Get-Content -LiteralPath $path -ErrorAction SilentlyContinue |
                Tee-Object -FilePath $LogPath -Append
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }

    Log "$File exit code: $exitCode"
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "$File failed with exit $exitCode."
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
"=== PIPA CLEAN ESP REBUILD START $(Get-Date -Format o) ===" |
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
if (-not (Test-Path -LiteralPath 'W:\Windows\System32\winload.efi')) {
    throw 'Windows ARM64 installation is missing winload.efi.'
}

$backup = Join-Path $BackupRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
New-Item -ItemType Directory -Force -Path $backup | Out-Null
Log "Backing up current ESP to $backup"
Run-Process robocopy.exe @('Z:\', $backup, '/E', '/R:1', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS', '/NP') `
    -TimeoutSeconds 180 -AllowFailure

if (Test-Path -LiteralPath 'W:\hiberfil.sys') {
    Log 'Deleting stale W:\hiberfil.sys'
    Remove-Item -LiteralPath 'W:\hiberfil.sys' -Force
}

$bcdPath = 'Z:\EFI\Microsoft\Boot\BCD'
if (Test-Path -LiteralPath $bcdPath) {
    $oldBcd = 'Z:\EFI\Microsoft\Boot\BCD.codex-old-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
    Move-Item -LiteralPath $bcdPath -Destination $oldBcd -Force
    Log "Moved old BCD to $oldBcd"
}
Get-ChildItem -LiteralPath 'Z:\EFI\Microsoft\Boot' -Filter 'BCD.LOG*' -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue

Run-Process bcdboot.exe @('W:\Windows', '/s', 'Z:', '/f', 'UEFI', '/c', '/v') -TimeoutSeconds 120
if (-not (Test-Path -LiteralPath $bcdPath)) {
    throw 'bcdboot returned success but did not create BCD.'
}

Run-Process bcdedit.exe @('/store', $bcdPath, '/set', '{default}', 'testsigning', 'on')
Run-Process bcdedit.exe @('/store', $bcdPath, '/set', '{default}', 'bootstatuspolicy', 'IgnoreAllFailures')
Run-Process bcdedit.exe @('/store', $bcdPath, '/set', '{default}', 'recoveryenabled', 'no')
Run-Process bcdedit.exe @('/store', $bcdPath, '/set', '{default}', 'bootlog', 'yes')
Run-Process bcdedit.exe @('/store', $bcdPath, '/deletevalue', '{default}', 'resumeobject') -AllowFailure
Run-Process bcdedit.exe @('/store', $bcdPath, '/enum', '{default}', '/v')

New-Item -ItemType Directory -Force -Path 'Z:\EFI\Boot' | Out-Null
Copy-Item -LiteralPath 'Z:\EFI\Microsoft\Boot\bootmgfw.efi' `
    -Destination 'Z:\EFI\Boot\bootaa64.efi' -Force

Get-FileHash -Algorithm SHA256 -LiteralPath @(
    'Z:\EFI\Boot\bootaa64.efi',
    'Z:\EFI\Microsoft\Boot\bootmgfw.efi',
    'Z:\EFI\Microsoft\Boot\BCD',
    'W:\Windows\Boot\EFI\bootmgfw.efi',
    'W:\Windows\System32\winload.efi'
) | Format-Table -AutoSize | Out-String |
    Tee-Object -FilePath $LogPath -Append | Write-Host

Log 'ESP_CLEAN_REBUILD_DONE'
"=== PIPA CLEAN ESP REBUILD END $(Get-Date -Format o) ===" |
    Add-Content -LiteralPath $LogPath

