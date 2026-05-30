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
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $Command 2>&1 | Out-File -FilePath $path -Encoding utf8
    } catch {
        "ERROR: $($_.Exception.Message)" | Out-File -FilePath $path -Encoding utf8
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

function Save-NativeCommand {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $FilePath,
        [Parameter(Mandatory)] [string[]] $Arguments,
        [int] $TimeoutSeconds = 45
    )

    $path = Join-Path $OutDir "$Name.txt"
    $argumentLine = ($Arguments | ForEach-Object {
        if ($_ -match '[\s"]') {
            '"' + ($_.Replace('\', '\\').Replace('"', '\"')) + '"'
        } else {
            $_
        }
    }) -join ' '

    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()

    try {
        $process = Start-Process `
            -FilePath $FilePath `
            -ArgumentList $argumentLine `
            -NoNewWindow `
            -PassThru `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill() } catch { }
            "ERROR: command timed out after $TimeoutSeconds seconds" | Out-File -FilePath $path -Encoding utf8
            return
        }

        $lines = @()
        $process.Refresh()
        $stdoutRaw = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw } else { '' }
        $stderrRaw = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { '' }
        $stdoutText = if ($null -eq $stdoutRaw) { '' } else { $stdoutRaw.TrimEnd() }
        $stderrText = if ($null -eq $stderrRaw) { '' } else { $stderrRaw.TrimEnd() }
        if ($stdoutText) { $lines += $stdoutText }
        if ($stderrText) { $lines += $stderrText }
        $lines += "EXITCODE=$($process.ExitCode)"
        $lines | Out-File -FilePath $path -Encoding utf8
    } catch {
        "ERROR: $($_.Exception.Message)" | Out-File -FilePath $path -Encoding utf8
    } finally {
        Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
    }
}

if ($UseAdb) {
    $adb = Resolve-LocalTool -Name 'adb' -ExplicitPath $AdbPath
    Write-Step "Collecting Android/ADB data"

    Save-NativeCommand 'adb-devices' $adb @('devices', '-l')
    Save-NativeCommand 'adb-getprop' $adb @('shell', 'getprop')
    Save-NativeCommand 'adb-cmdline' $adb @('shell', 'cat', '/proc/cmdline')
    Save-NativeCommand 'adb-partitions' $adb @('shell', 'cat', '/proc/partitions')
    Save-NativeCommand 'adb-by-name' $adb @('shell', 'ls', '-l', '/dev/block/by-name')
    Save-NativeCommand 'adb-mounts' $adb @('shell', 'mount')
    Save-NativeCommand 'adb-input' $adb @('shell', 'sh', '-c', 'ls -l /dev/input; cat /proc/bus/input/devices')
    Save-NativeCommand 'adb-dmesg-filtered' $adb @('shell', 'sh', '-c', "dmesg | grep -Ei 'adreno|gpu|dsi|touch|goodix|novatek|i2c|camera|cam|cci|csiphy|csid|qcom|wifi|bt|battery|charger' || true")
}

if ($UseFastboot) {
    $fastboot = Resolve-LocalTool -Name 'fastboot' -ExplicitPath $FastbootPath
    Write-Step "Collecting fastboot data"

    Save-NativeCommand 'fastboot-devices' $fastboot @('devices')
    Save-NativeCommand 'fastboot-vars' $fastboot @('getvar', 'all')
    Save-NativeCommand 'fastboot-product' $fastboot @('getvar', 'product')
    Save-NativeCommand 'fastboot-current-slot' $fastboot @('getvar', 'current-slot')
    Save-NativeCommand 'fastboot-unlocked' $fastboot @('getvar', 'unlocked')
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
