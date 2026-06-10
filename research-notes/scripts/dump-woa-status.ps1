param(
  [string]$OutDir = "C:\woa"
)

$ErrorActionPreference = "Continue"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$log = Join-Path $OutDir "status-dump.log"
function Write-Log {
  param([string]$Message)
  $line = "{0}  {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $Message
  $line | Tee-Object -FilePath $log -Append
}

Write-Log "=== WOA status dump ==="

$commands = @(
  @{ Name = "display"; Args = @("/enum-devices", "/class", "Display", "/connected", "/drivers") },
  @{ Name = "keyboard"; Args = @("/enum-devices", "/class", "Keyboard", "/connected", "/drivers") },
  @{ Name = "hid"; Args = @("/enum-devices", "/class", "HIDClass", "/connected", "/drivers") },
  @{ Name = "system"; Args = @("/enum-devices", "/class", "System", "/connected", "/drivers") },
  @{ Name = "problem"; Args = @("/enum-devices", "/problem", "/ids", "/drivers") },
  @{ Name = "all"; Args = @("/enum-devices", "/ids", "/drivers") }
)

foreach ($cmd in $commands) {
  $path = Join-Path $OutDir ("status-{0}.txt" -f $cmd.Name)
  Write-Log ("pnputil {0} -> {1}" -f ($cmd.Args -join " "), $path)
  & pnputil.exe @($cmd.Args) > $path 2>&1
}

$csv = Join-Path $OutDir "status-pnp.csv"
Get-PnpDevice -PresentOnly:$false |
  Select-Object Status,Class,FriendlyName,InstanceId,Problem |
  Sort-Object Class,FriendlyName,InstanceId |
  Export-Csv -NoTypeInformation -Path $csv
Write-Log "Wrote $csv"

$interesting = Join-Path $OutDir "status-interesting.txt"
Get-PnpDevice -PresentOnly:$false |
  Where-Object {
    $_.InstanceId -match "QCOM|NTTS|NVT|NTP|NANOSIC|VID_3206|VID_258A|BASICDISPLAY|DISPLAY|TOUCH|I2C|GPIO|PMIC|PEP|BATT"
  } |
  Sort-Object Class,FriendlyName,InstanceId |
  Format-List Status,Class,FriendlyName,InstanceId,Problem |
  Out-File -Encoding utf8 -FilePath $interesting
Write-Log "Wrote $interesting"

Write-Log "=== done ==="

