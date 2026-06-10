param(
    [string] $EsdPath = '<ARTIFACT_DIR>\26200.8524.260521-2110.25H2_GE_RELEASE_SVC_PROD3_CLIENTMULTI_A64FRE_EN-US.esd',
    [int] $ImageIndex = 6,
    [string] $DriverPath = 'D:\pipa-drivers\kona-core-staged-20260531',
    [string] $LogPath = '<ARTIFACT_DIR>\apply-win11-index6-elevated-20260531.log'
)

$ErrorActionPreference = 'Stop'

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

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath) | Out-Null
"=== PIPA WINDOWS APPLY START $(Get-Date -Format o) ===" | Set-Content -LiteralPath $LogPath -Encoding UTF8

Write-Step "Finding Xiaomi Pad mass-storage disk"
$disk = Get-Disk |
    Where-Object {
        $_.BusType -eq 'USB' -and
        $_.FriendlyName -eq 'Linux File-Stor Gadget' -and
        $_.PartitionStyle -eq 'GPT' -and
        $_.Size -gt 200GB
    } |
    Sort-Object Number |
    Select-Object -First 1

if (-not $disk) {
    throw "Mass-storage disk not found. Expected USB GPT disk named 'Linux File-Stor Gadget'."
}

Write-Step "Target disk number: $($disk.Number), size: $($disk.Size)"
$esp = Get-Partition -DiskNumber $disk.Number -PartitionNumber 35
$win = Get-Partition -DiskNumber $disk.Number -PartitionNumber 36
$userdata = Get-Partition -DiskNumber $disk.Number -PartitionNumber 34

if ($userdata.Size -lt 100GB) {
    throw "Safety check failed: partition 34 does not look like userdata."
}
if ($esp.GptType -ne '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}') {
    throw "Safety check failed: partition 35 is not EFI System Partition. Type=$($esp.GptType)"
}
if ($win.GptType -ne '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}') {
    throw "Safety check failed: partition 36 is not Microsoft Basic Data. Type=$($win.GptType)"
}

Write-Step "Assigning drive letters"
if ($esp.DriveLetter -ne 'Y') {
    if ($esp.DriveLetter -and $esp.DriveLetter -ne [char]0) {
        Set-Partition -DiskNumber $disk.Number -PartitionNumber 35 -NewDriveLetter Y
    } else {
        Set-Partition -DiskNumber $disk.Number -PartitionNumber 35 -NewDriveLetter Y
    }
}
if ($win.DriveLetter -ne 'E') {
    if ($win.DriveLetter -and $win.DriveLetter -ne [char]0) {
        Set-Partition -DiskNumber $disk.Number -PartitionNumber 36 -NewDriveLetter E
    } else {
        Set-Partition -DiskNumber $disk.Number -PartitionNumber 36 -NewDriveLetter E
    }
}

Write-Step "Formatting only ESP partition 35 and Windows partition 36"
Format-Volume -DriveLetter Y -FileSystem FAT32 -NewFileSystemLabel ESPPIPA -Confirm:$false -Force | Out-Null
Format-Volume -DriveLetter E -FileSystem NTFS -NewFileSystemLabel WINPIPA -Confirm:$false -Force | Out-Null

Write-Step "Applying Windows image index $ImageIndex"
Invoke-Logged -Exe dism.exe -ArgumentList @(
    '/Apply-Image',
    "/ImageFile:$EsdPath",
    "/Index:$ImageIndex",
    '/ApplyDir:E:\'
)

if (Test-Path -LiteralPath $DriverPath) {
    Write-Step "Injecting Kona drivers from $DriverPath"
    Invoke-Logged -Exe dism.exe -ArgumentList @(
        '/Image:E:\',
        '/Add-Driver',
        "/Driver:$DriverPath",
        '/Recurse'
    )
} else {
    Write-Step "Driver path missing, skipping driver injection: $DriverPath"
}

Write-Step "Creating UEFI boot files"
Invoke-Logged -Exe bcdboot.exe -ArgumentList @('E:\Windows', '/s', 'Y:', '/f', 'UEFI')

Write-Step "Enabling test signing in offline BCD"
Invoke-Logged -Exe bcdedit.exe -ArgumentList @('/store', 'Y:\EFI\Microsoft\Boot\BCD', '/set', '{default}', 'testsigning', 'on')

Write-Step "Patching offline SYSTEM USB role"
reg.exe load HKLM\PIPA_SYSTEM E:\Windows\System32\Config\SYSTEM | Tee-Object -FilePath $LogPath -Append
try {
    New-Item -Path 'HKLM:\PIPA_SYSTEM\ControlSet001\Control\USB' -Force | Out-Null
    New-ItemProperty -Path 'HKLM:\PIPA_SYSTEM\ControlSet001\Control\USB' -Name 'OsDefaultRoleSwitchMode' -PropertyType DWord -Value 1 -Force | Out-Null
} finally {
    reg.exe unload HKLM\PIPA_SYSTEM | Tee-Object -FilePath $LogPath -Append
}

Write-Step "Patching offline SOFTWARE OOBE conveniences"
reg.exe load HKLM\PIPA_SOFTWARE E:\Windows\System32\Config\SOFTWARE | Tee-Object -FilePath $LogPath -Append
try {
    New-Item -Path 'HKLM:\PIPA_SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' -Force | Out-Null
    New-ItemProperty -Path 'HKLM:\PIPA_SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' -Name 'DefaultAccountAction' -PropertyType DWord -Value 0 -Force | Out-Null
    New-ItemProperty -Path 'HKLM:\PIPA_SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' -Name 'LaunchUserOOBE' -PropertyType DWord -Value 0 -Force | Out-Null
    New-Item -Path 'HKLM:\PIPA_SOFTWARE\Policies\Microsoft\Windows\OOBE' -Force | Out-Null
    New-ItemProperty -Path 'HKLM:\PIPA_SOFTWARE\Policies\Microsoft\Windows\OOBE' -Name 'DisablePrivacyExperience' -PropertyType DWord -Value 1 -Force | Out-Null
} finally {
    reg.exe unload HKLM\PIPA_SOFTWARE | Tee-Object -FilePath $LogPath -Append
}

Write-Step "Final volumes"
Get-Volume -DriveLetter E,Y | Select-Object DriveLetter,FileSystemLabel,FileSystem,SizeRemaining,Size |
    Format-Table -AutoSize | Tee-Object -FilePath $LogPath -Append

Write-Step "DONE"
"=== PIPA WINDOWS APPLY END $(Get-Date -Format o) ===" | Add-Content -LiteralPath $LogPath

