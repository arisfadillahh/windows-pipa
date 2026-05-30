[CmdletBinding()]
param(
    [switch] $UseAdb,
    [switch] $UseFastboot,
    [switch] $UseSsh,
    [string] $AdbPath,
    [string] $FastbootPath,
    [string] $SshHost = '172.16.42.1',
    [string] $SshUser = 'user',
    [string] $OutDir
)

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\Common.psm1" -Force

Assert-Windows

if (-not $UseAdb -and -not $UseFastboot -and -not $UseSsh) {
    $UseAdb = $true
}

if (-not $OutDir) {
    $OutDir = New-CaptureDirectory -Prefix 'pipa'
} else {
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
}

Write-Step "Writing capture files to $OutDir"

function Save-Command {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [scriptblock] $Command
    )

    $path = Join-Path $OutDir "$Name.txt"
    try {
        & $Command 2>&1 | Out-File -FilePath $path -Encoding utf8
    } catch {
        "ERROR: $($_.Exception.Message)" | Out-File -FilePath $path -Encoding utf8
    }
}

if ($UseAdb) {
    $adb = Resolve-LocalTool -Name 'adb' -ExplicitPath $AdbPath
    Write-Step "Collecting Android/ADB data"

    Save-Command 'adb-devices' { & $adb devices -l }
    Save-Command 'adb-getprop' { & $adb shell getprop }
    Save-Command 'adb-cmdline' { & $adb shell cat /proc/cmdline }
    Save-Command 'adb-partitions' { & $adb shell cat /proc/partitions }
    Save-Command 'adb-by-name' { & $adb shell ls -l /dev/block/by-name }
    Save-Command 'adb-mounts' { & $adb shell mount }
    Save-Command 'adb-input' { & $adb shell ls -l /dev/input; & $adb shell cat /proc/bus/input/devices }
    Save-Command 'adb-dmesg-filtered' { & $adb shell dmesg | Select-String -Pattern 'adreno|gpu|dsi|touch|goodix|novatek|i2c|camera|cam|cci|csiphy|csid|qcom|wifi|bt|battery|charger' }
}

if ($UseFastboot) {
    $fastboot = Resolve-LocalTool -Name 'fastboot' -ExplicitPath $FastbootPath
    Write-Step "Collecting fastboot data"

    Save-Command 'fastboot-devices' { & $fastboot devices }
    Save-Command 'fastboot-vars' { & $fastboot getvar all }
    Save-Command 'fastboot-product' { & $fastboot getvar product }
    Save-Command 'fastboot-current-slot' { & $fastboot getvar current-slot }
    Save-Command 'fastboot-unlocked' { & $fastboot getvar unlocked }
}

if ($UseSsh) {
    $sshTarget = "$SshUser@$SshHost"
    Write-Step "Collecting postmarketOS/Linux data through SSH at $sshTarget"

    Save-Command 'ssh-uname' { ssh $sshTarget 'uname -a' }
    Save-Command 'ssh-model' { ssh $sshTarget 'cat /proc/device-tree/model 2>/dev/null; echo; cat /proc/device-tree/compatible 2>/dev/null; echo' }
    Save-Command 'ssh-lsblk' { ssh $sshTarget 'lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,PARTLABEL,PARTUUID,MOUNTPOINTS' }
    Save-Command 'ssh-by-name' { ssh $sshTarget 'ls -l /dev/block/by-name 2>/dev/null || true' }
    Save-Command 'ssh-drm' { ssh $sshTarget 'find /sys/class/drm -maxdepth 3 -type f -print 2>/dev/null | sort | xargs -r -I{} sh -c "echo --- {}; cat {} 2>/dev/null"' }
    Save-Command 'ssh-input' { ssh $sshTarget 'cat /proc/bus/input/devices; echo; ls -l /dev/input' }
    Save-Command 'ssh-i2c' { ssh $sshTarget 'find /sys/bus/i2c/devices -maxdepth 2 -type f -name name -print -exec cat {} \; 2>/dev/null' }
    Save-Command 'ssh-dmesg-filtered' { ssh $sshTarget "dmesg | grep -Ei 'adreno|gpu|dsi|touch|goodix|novatek|i2c|camera|cam|cci|csiphy|csid|qcom|wifi|bt|battery|charger' || true" }
}

Write-Step "Capture complete"
