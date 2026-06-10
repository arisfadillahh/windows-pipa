param(
    [string] $EsdPath = '<ARTIFACT_DIR>\26200.8524.260521-2110.25H2_GE_RELEASE_SVC_PROD3_CLIENTMULTI_A64FRE_EN-US.esd',
    [int] $ImageIndex = 6,
    [string] $ProjectRoot = '<PROJECT_ROOT>',
    [string] $WorkspaceRoot = '<WORKSPACE>',
    [string] $LogPath = '<ARTIFACT_DIR>\fresh-reinstall-checkpoint-20260604.log'
)

$ErrorActionPreference = 'Stop'
$WindowsLetter = 'W'
$EspLetter = 'Z'

function Write-Step {
    param([string] $Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    Add-Content -LiteralPath $LogPath -Value $line
}

function Invoke-Logged {
    param(
        [string] $Exe,
        [string[]] $ArgumentList
    )
    Write-Step ("RUN " + $Exe + " " + ($ArgumentList -join ' '))
    & $Exe @ArgumentList 2>&1 | Tee-Object -FilePath $LogPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "$Exe exited with $LASTEXITCODE"
    }
}

function Invoke-Robocopy {
    param(
        [string] $Source,
        [string] $Destination
    )
    Write-Step "COPY $Source -> $Destination"
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    & robocopy.exe $Source $Destination /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP 2>&1 |
        Tee-Object -FilePath $LogPath -Append
    if ($LASTEXITCODE -gt 7) {
        throw "robocopy exited with $LASTEXITCODE for $Source"
    }
}

function Ensure-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        return
    }

    $args = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process -FilePath powershell.exe -ArgumentList $args -Verb RunAs
    exit
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
        throw "Drive letter $Letter is occupied by disk $($occupied.DiskNumber) partition $($occupied.PartitionNumber)"
    }

    $partition = Get-Partition -DiskNumber $DiskNumber -PartitionNumber $PartitionNumber
    if ($partition.DriveLetter -ne $Letter) {
        Set-Partition -DiskNumber $DiskNumber -PartitionNumber $PartitionNumber -NewDriveLetter $Letter
    }
}

Ensure-Admin
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath) | Out-Null
"=== PIPA FRESH REINSTALL START $(Get-Date -Format o) ===" |
    Set-Content -LiteralPath $LogPath -Encoding UTF8

foreach ($required in @(
    $EsdPath,
    (Join-Path $WorkspaceRoot 'fresh-payload\unattend.xml'),
    (Join-Path $WorkspaceRoot 'fresh-payload\SetupComplete.cmd'),
    (Join-Path $WorkspaceRoot 'fresh-payload\continue-driver-checkpoint.ps1'),
    (Join-Path $WorkspaceRoot 'scripts\install-drivers-no-power.ps1'),
    (Join-Path $WorkspaceRoot 'scripts\dump-woa-status.ps1'),
    (Join-Path $WorkspaceRoot 'CHECKPOINT-FRESH-REINSTALL-20260604.md'),
    (Join-Path $ProjectRoot 'kona-drivers\Drivers\Graphics\DXKM'),
    (Join-Path $ProjectRoot 'kona-drivers\Drivers\Graphics\QDCM'),
    (Join-Path $ProjectRoot 'pad6-touch-driver'),
    (Join-Path $ProjectRoot 'pad6-keyboard-driver')
)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required path missing: $required"
    }
}

Write-Step 'Finding Xiaomi Pad whole-disk mass-storage target'
$candidates = @(Get-Disk | Where-Object {
    $_.BusType -eq 'USB' -and
    $_.FriendlyName -eq 'Linux File-Stor Gadget' -and
    $_.PartitionStyle -eq 'GPT' -and
    $_.Size -gt 200GB -and
    $_.Size -lt 300GB
})
if ($candidates.Count -ne 1) {
    throw "Expected exactly one 200-300GB USB GPT Linux File-Stor Gadget; found $($candidates.Count)"
}
$disk = $candidates[0]
$userdata = Get-Partition -DiskNumber $disk.Number -PartitionNumber 34
$esp = Get-Partition -DiskNumber $disk.Number -PartitionNumber 35
$windows = Get-Partition -DiskNumber $disk.Number -PartitionNumber 36

if ($userdata.Size -lt 100GB -or $userdata.Size -gt 150GB) {
    throw "Safety check failed: partition 34 does not look like Android userdata. Size=$($userdata.Size)"
}
if ($esp.Size -lt 400MB -or $esp.Size -gt 700MB) {
    throw "Safety check failed: partition 35 does not look like ESP. Size=$($esp.Size)"
}
if ($windows.Size -lt 60GB -or $windows.Size -gt 75GB) {
    throw "Safety check failed: partition 36 does not look like WINPIPA. Size=$($windows.Size)"
}
if ($esp.GptType -ne '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}') {
    throw "Safety check failed: partition 35 is not EFI System Partition. Type=$($esp.GptType)"
}
if ($windows.GptType -ne '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}') {
    throw "Safety check failed: partition 36 is not Microsoft Basic Data. Type=$($windows.GptType)"
}

Write-Step "Verified target disk $($disk.Number). Android userdata partition 34 will not be touched."
Set-TargetLetter -DiskNumber $disk.Number -PartitionNumber 35 -Letter $EspLetter
Set-TargetLetter -DiskNumber $disk.Number -PartitionNumber 36 -Letter $WindowsLetter

Write-Step 'Formatting only partition 35 ESP and partition 36 Windows'
Format-Volume -DriveLetter $EspLetter -FileSystem FAT32 -NewFileSystemLabel ESPPIPA -Confirm:$false -Force | Out-Null
Format-Volume -DriveLetter $WindowsLetter -FileSystem NTFS -NewFileSystemLabel WINPIPA -Confirm:$false -Force | Out-Null

$winRoot = "$WindowsLetter`:\"
$espRoot = "$EspLetter`:\"
Write-Step "Applying Windows Pro ARM64 image index $ImageIndex"
Invoke-Logged -Exe dism.exe -ArgumentList @(
    '/Apply-Image',
    "/ImageFile:$EsdPath",
    "/Index:$ImageIndex",
    "/ApplyDir:$winRoot"
)

Write-Step 'Staging checkpoint, scripts, and no-power driver payload'
$woaRoot = Join-Path $winRoot 'woa'
$payloadRoot = Join-Path $WorkspaceRoot 'fresh-payload'
$setupScripts = Join-Path $winRoot 'Windows\Setup\Scripts'
$panther = Join-Path $winRoot 'Windows\Panther'
New-Item -ItemType Directory -Force -Path $woaRoot, $setupScripts, $panther | Out-Null

Copy-Item -LiteralPath (Join-Path $WorkspaceRoot 'CHECKPOINT-FRESH-REINSTALL-20260604.md') -Destination (Join-Path $woaRoot 'CHECKPOINT.md') -Force
Copy-Item -LiteralPath (Join-Path $WorkspaceRoot 'scripts\install-drivers-no-power.ps1') -Destination (Join-Path $woaRoot 'install-drivers-no-power.ps1') -Force
Copy-Item -LiteralPath (Join-Path $WorkspaceRoot 'scripts\dump-woa-status.ps1') -Destination (Join-Path $woaRoot 'dump-woa-status.ps1') -Force
Copy-Item -LiteralPath (Join-Path $payloadRoot 'continue-driver-checkpoint.ps1') -Destination (Join-Path $woaRoot 'continue-driver-checkpoint.ps1') -Force
Copy-Item -LiteralPath (Join-Path $payloadRoot 'SetupComplete.cmd') -Destination (Join-Path $setupScripts 'SetupComplete.cmd') -Force
Copy-Item -LiteralPath (Join-Path $payloadRoot 'unattend.xml') -Destination (Join-Path $panther 'unattend.xml') -Force
Copy-Item -LiteralPath (Join-Path $payloadRoot 'unattend.xml') -Destination (Join-Path $winRoot 'unattend.xml') -Force

$driverRoot = Join-Path $woaRoot 'drivers'
Invoke-Robocopy -Source (Join-Path $ProjectRoot 'kona-drivers\Drivers\Graphics\DXKM') -Destination (Join-Path $driverRoot 'kona-graphics\DXKM')
Invoke-Robocopy -Source (Join-Path $ProjectRoot 'kona-drivers\Drivers\Graphics\QDCM') -Destination (Join-Path $driverRoot 'kona-graphics\QDCM')
Invoke-Robocopy -Source (Join-Path $ProjectRoot 'pad6-touch-driver') -Destination (Join-Path $driverRoot 'pad6-touch-driver')
Invoke-Robocopy -Source (Join-Path $ProjectRoot 'pad6-keyboard-driver') -Destination (Join-Path $driverRoot 'pad6-keyboard-driver')

Write-Step 'Creating UEFI boot files'
Invoke-Logged -Exe bcdboot.exe -ArgumentList @(
    (Join-Path $winRoot 'Windows'),
    '/s',
    "$EspLetter`:",
    '/f',
    'UEFI'
)
Invoke-Logged -Exe bcdedit.exe -ArgumentList @(
    '/store',
    (Join-Path $espRoot 'EFI\Microsoft\Boot\BCD'),
    '/set',
    '{default}',
    'testsigning',
    'on'
)

Write-Step 'Setting offline USB role and OOBE fallback'
reg.exe load HKLM\PIPA_FRESH_SYSTEM (Join-Path $winRoot 'Windows\System32\Config\SYSTEM') |
    Tee-Object -FilePath $LogPath -Append
try {
    New-Item -Path 'HKLM:\PIPA_FRESH_SYSTEM\ControlSet001\Control\USB' -Force | Out-Null
    New-ItemProperty -Path 'HKLM:\PIPA_FRESH_SYSTEM\ControlSet001\Control\USB' -Name 'OsDefaultRoleSwitchMode' -PropertyType DWord -Value 1 -Force | Out-Null
} finally {
    reg.exe unload HKLM\PIPA_FRESH_SYSTEM | Tee-Object -FilePath $LogPath -Append
}

reg.exe load HKLM\PIPA_FRESH_SOFTWARE (Join-Path $winRoot 'Windows\System32\Config\SOFTWARE') |
    Tee-Object -FilePath $LogPath -Append
try {
    New-Item -Path 'HKLM:\PIPA_FRESH_SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' -Force | Out-Null
    New-ItemProperty -Path 'HKLM:\PIPA_FRESH_SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' -Name 'BypassNRO' -PropertyType DWord -Value 1 -Force | Out-Null
    New-Item -Path 'HKLM:\PIPA_FRESH_SOFTWARE\Policies\Microsoft\Windows\OOBE' -Force | Out-Null
    New-ItemProperty -Path 'HKLM:\PIPA_FRESH_SOFTWARE\Policies\Microsoft\Windows\OOBE' -Name 'DisablePrivacyExperience' -PropertyType DWord -Value 1 -Force | Out-Null
} finally {
    reg.exe unload HKLM\PIPA_FRESH_SOFTWARE | Tee-Object -FilePath $LogPath -Append
}

Write-Step 'Writing install manifest'
$manifest = [ordered]@{
    InstalledAt = (Get-Date -Format o)
    TargetDisk = $disk.Number
    AndroidPartitionUntouched = 34
    EspPartitionFormatted = 35
    WindowsPartitionFormatted = 36
    EsdPath = $EsdPath
    ImageIndex = $ImageIndex
    User = 'Goffath'
    DriverContinuation = 'Pipa WOA Driver Continuation'
    DriverMode = 'no-power allowlist: GPU, touch, keyboard'
}
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $woaRoot 'fresh-install-manifest.json') -Encoding UTF8

Write-Step 'Final target volumes'
Get-Volume -DriveLetter $WindowsLetter, $EspLetter |
    Select-Object DriveLetter, FileSystemLabel, FileSystem, SizeRemaining, Size |
    Format-Table -AutoSize |
    Tee-Object -FilePath $LogPath -Append

Write-Step 'DONE. Fresh Windows is staged; restore stable UEFI v8 to boot_b before boot.'
"=== PIPA FRESH REINSTALL END $(Get-Date -Format o) ===" |
    Add-Content -LiteralPath $LogPath


