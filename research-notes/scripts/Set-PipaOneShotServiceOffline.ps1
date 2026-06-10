param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Z]:$')]
    [string]$WinDrive,

    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ })]
    [string]$PayloadScript,

    [string]$ServiceName = 'PipaOneShot',
    [string]$TargetDir = 'woa\oneshot'
)

$ErrorActionPreference = 'Stop'

function Write-Log($Message) {
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$stamp] $Message"
}

$winRoot = Join-Path $WinDrive 'Windows'
$systemHive = Join-Path $winRoot 'System32\Config\SYSTEM'

$destDir = Join-Path $WinDrive $TargetDir
New-Item -ItemType Directory -Force -Path $destDir | Out-Null

$payloadName = Split-Path -Leaf $PayloadScript
$destPayload = Join-Path $destDir $payloadName
Copy-Item -LiteralPath $PayloadScript -Destination $destPayload -Force

$serviceBootstrap = @"
`$ErrorActionPreference = 'Continue'
`$serviceName = '$ServiceName'
`$logDir = 'C:\$TargetDir\logs'
New-Item -ItemType Directory -Force -Path `$logDir | Out-Null
`$log = Join-Path `$logDir ('bootstrap-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
Start-Transcript -LiteralPath `$log -Force | Out-Null
try {
    reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\`$serviceName" /v Start /t REG_DWORD /d 4 /f | Out-Host
    Start-Sleep -Seconds 20
    & 'C:\$TargetDir\$payloadName'
} catch {
    `$_.Exception | Format-List * -Force | Out-String | Write-Host
} finally {
    Stop-Transcript | Out-Null
}
"@

$bootstrapPath = Join-Path $destDir 'Run-PipaOneShot.ps1'
Set-Content -LiteralPath $bootstrapPath -Value $serviceBootstrap -Encoding ASCII

function Install-LocalGpoFallback {
    $gpRoot = Join-Path $WinDrive 'Windows\System32\GroupPolicy'
    $gpScripts = Join-Path $gpRoot 'Machine\Scripts'
    $gpStartup = Join-Path $gpScripts 'Startup'
    New-Item -ItemType Directory -Force -Path $gpStartup | Out-Null

    $cmd = @"
@echo off
set LOGDIR=C:\$TargetDir\logs
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
echo %DATE% %TIME% Local GPO startup invoked>>"%LOGDIR%\gpo-startup.log"
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\$TargetDir\Run-PipaOneShot.ps1" >>"%LOGDIR%\gpo-startup.log" 2>>&1
echo %DATE% %TIME% Local GPO startup finished>>"%LOGDIR%\gpo-startup.log"
"@
    Set-Content -LiteralPath (Join-Path $gpStartup 'Run-PipaOneShot.cmd') -Value $cmd -Encoding ASCII

    $scriptsIni = @"
[Startup]
0CmdLine=Run-PipaOneShot.cmd
0Parameters=
"@
    Set-Content -LiteralPath (Join-Path $gpScripts 'scripts.ini') -Value $scriptsIni -Encoding Unicode

    $gpt = @"
[General]
gPCMachineExtensionNames=[{42B5FAAE-6536-11d2-AE5A-0000F87571E3}{40B6664F-4972-11D1-A7CA-0000F87571E3}]
Version=65536
displayName=Local Group Policy
"@
    Set-Content -LiteralPath (Join-Path $gpRoot 'gpt.ini') -Value $gpt -Encoding ASCII
    Write-Log "Installed Local Group Policy startup fallback at $gpStartup"
}

$hiveName = 'PIPA_ONESHOT_SYSTEM'
$loaded = $false
$serviceInstalled = $false
try {
    $alreadyLoaded = Test-Path "HKLM:\$hiveName"
    if (-not $alreadyLoaded) {
        Write-Log "Loading offline SYSTEM hive from $systemHive"
        & reg.exe load "HKLM\$hiveName" $systemHive | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Log "reg load failed with exit code $LASTEXITCODE; using file-only Local GPO fallback"
            Install-LocalGpoFallback
            return
        }
        $loaded = $true
    }

    $controlSets = Get-ChildItem "HKLM:\$hiveName" |
        Where-Object { $_.PSChildName -match '^ControlSet\d{3}$' } |
        Select-Object -ExpandProperty PSChildName

    if (-not $controlSets) {
        throw 'No ControlSet00x keys found in offline SYSTEM hive'
    }

    $imagePath = 'C:\Windows\System32\cmd.exe /c start "" /min C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\' + $TargetDir + '\Run-PipaOneShot.ps1"'

    foreach ($cs in $controlSets) {
        $svc = "HKLM:\$hiveName\$cs\Services\$ServiceName"
        Write-Log "Writing one-shot service $ServiceName to $cs"
        New-Item -Path $svc -Force | Out-Null
        New-ItemProperty -Path $svc -Name Type -PropertyType DWord -Value 0x10 -Force | Out-Null
        New-ItemProperty -Path $svc -Name Start -PropertyType DWord -Value 2 -Force | Out-Null
        New-ItemProperty -Path $svc -Name ErrorControl -PropertyType DWord -Value 0 -Force | Out-Null
        New-ItemProperty -Path $svc -Name ImagePath -PropertyType ExpandString -Value $imagePath -Force | Out-Null
        New-ItemProperty -Path $svc -Name DisplayName -PropertyType String -Value 'Pipa one-shot test runner' -Force | Out-Null
        New-ItemProperty -Path $svc -Name ObjectName -PropertyType String -Value 'LocalSystem' -Force | Out-Null
        New-ItemProperty -Path $svc -Name DependOnService -PropertyType MultiString -Value @('PlugPlay') -Force | Out-Null
    }
    $serviceInstalled = $true
} finally {
    if ($loaded) {
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
        Write-Log "Unloading offline SYSTEM hive"
        & reg.exe unload "HKLM\$hiveName" | Out-Host
    }
}

Write-Log "Installed one-shot payload at $destPayload"
if (-not $serviceInstalled) {
    Write-Log "Installed one-shot payload at $destPayload"
}
Write-Log "Result/logs will be under C:\$TargetDir on next Windows boot"

