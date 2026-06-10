param(
    [string]$TraceName = "PipaBootTrace"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Result = Join-Path $Root "RESULT.txt"
$Done = Join-Path $Root "DONE.txt"
$ProvidersFile = Join-Path $Root "providers.txt"
$TraceDir = "C:\Renegade\Logfiles"
$TraceFile = Join-Path $TraceDir "$TraceName.etl"
$StopScript = Join-Path $Root "stop-afterboot.ps1"
$TaskName = "PipaBootTraceStop"

function Add-Line([string]$Message) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    $line | Tee-Object -FilePath $Result -Append
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

New-Item -ItemType Directory -Force -Path $Root | Out-Null
Remove-Item -LiteralPath $Result,$Done -Force -ErrorAction SilentlyContinue
Add-Line "=== PIPA BOOT TRACE LIVE SETUP START ==="
Add-Line "Running as $env:USERDOMAIN\$env:USERNAME"

if (!(Test-Admin)) {
    Add-Line "Not elevated. Requesting UAC."
    $args = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $args
    Add-Line "Spawned elevated setup; exiting launcher."
    exit 0
}

if (!(Test-Path -LiteralPath $ProvidersFile)) {
    throw "Missing provider list: $ProvidersFile"
}

$providers = Get-Content -LiteralPath $ProvidersFile | Where-Object { $_ -match "^[0-9a-fA-F-]{36}$" } | Sort-Object -Unique
if (!$providers -or $providers.Count -eq 0) {
    throw "Provider list is empty."
}

New-Item -ItemType Directory -Force -Path $TraceDir | Out-Null

$base = "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\$TraceName"
if (Test-Path $base) {
    Remove-Item -Path $base -Recurse -Force
}
New-Item -Path $base -Force | Out-Null
New-ItemProperty -Path $base -Name "Start" -PropertyType DWord -Value 1 -Force | Out-Null
New-ItemProperty -Path $base -Name "Guid" -PropertyType String -Value "{b23a2668-6d11-4d4e-a704-f3a0f6d4a5f8}" -Force | Out-Null
New-ItemProperty -Path $base -Name "FileName" -PropertyType String -Value $TraceFile -Force | Out-Null
New-ItemProperty -Path $base -Name "LogFileMode" -PropertyType DWord -Value 2 -Force | Out-Null
New-ItemProperty -Path $base -Name "MaximumFileSize" -PropertyType DWord -Value 256 -Force | Out-Null
New-ItemProperty -Path $base -Name "BufferSize" -PropertyType DWord -Value 1024 -Force | Out-Null
New-ItemProperty -Path $base -Name "MinimumBuffers" -PropertyType DWord -Value 16 -Force | Out-Null
New-ItemProperty -Path $base -Name "MaximumBuffers" -PropertyType DWord -Value 128 -Force | Out-Null

foreach ($provider in $providers) {
    $key = Join-Path $base "{$provider}"
    New-Item -Path $key -Force | Out-Null
    New-ItemProperty -Path $key -Name "Enabled" -PropertyType DWord -Value 1 -Force | Out-Null
    New-ItemProperty -Path $key -Name "EnableFlags" -PropertyType DWord -Value 0xffffffff -Force | Out-Null
    New-ItemProperty -Path $key -Name "EnableLevel" -PropertyType DWord -Value 0xff -Force | Out-Null
}

@"
`$ErrorActionPreference = "Continue"
`$Root = "$Root"
`$Result = Join-Path `$Root "STOP-RESULT.txt"
function Add-Line([string]`$Message) {
    "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), `$Message | Tee-Object -FilePath `$Result -Append
}
Add-Line "PipaBootTrace post-boot stop task start."
Start-Sleep -Seconds 120
logman.exe stop $TraceName -ets 2>&1 | Tee-Object -FilePath `$Result -Append
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\$TraceName" -Name Start -Type DWord -Value 0
schtasks.exe /Delete /TN "$TaskName" /F 2>&1 | Tee-Object -FilePath `$Result -Append
"done $(Get-Date -Format o)" | Set-Content -LiteralPath (Join-Path `$Root "STOP-DONE.txt") -Encoding ASCII
Add-Line "PipaBootTrace post-boot stop task done."
"@ | Set-Content -LiteralPath $StopScript -Encoding ASCII

$taskCmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$StopScript`""
schtasks.exe /Create /TN $TaskName /SC ONSTART /RU SYSTEM /RL HIGHEST /TR $taskCmd /F | Tee-Object -FilePath $Result -Append

Add-Line "Configured $TraceName with $($providers.Count) providers."
Add-Line "Trace target: $TraceFile"
Add-Line "Scheduled $TaskName to stop trace and disable autologger after boot."
"done $(Get-Date -Format o)" | Set-Content -LiteralPath $Done -Encoding ASCII
Add-Line "Rebooting in 8 seconds."
Start-Sleep -Seconds 8
shutdown.exe /r /t 0

