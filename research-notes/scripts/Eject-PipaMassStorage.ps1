$ErrorActionPreference = 'Stop'
$LogPath = '<ARTIFACT_DIR>\fresh-reinstall-eject-20260604.log'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

"=== PIPA MASS STORAGE EJECT START $(Get-Date -Format o) ===" |
    Set-Content -LiteralPath $LogPath -Encoding UTF8

$candidates = @(Get-Disk | Where-Object {
    $_.BusType -eq 'USB' -and
    $_.FriendlyName -eq 'Linux File-Stor Gadget' -and
    $_.PartitionStyle -eq 'GPT' -and
    $_.Size -gt 200GB -and
    $_.Size -lt 300GB
})
if ($candidates.Count -ne 1) {
    throw "Expected one pipa mass-storage disk; found $($candidates.Count)"
}

$disk = $candidates[0]
$userdata = Get-Partition -DiskNumber $disk.Number -PartitionNumber 34
$esp = Get-Partition -DiskNumber $disk.Number -PartitionNumber 35
$windows = Get-Partition -DiskNumber $disk.Number -PartitionNumber 36
if ($userdata.Size -lt 100GB -or $windows.Size -lt 60GB -or $esp.Size -lt 400MB) {
    throw 'Partition safety verification failed'
}

Write-Output "Verified disk $($disk.Number), offlining now" |
    Tee-Object -FilePath $LogPath -Append
Set-Disk -Number $disk.Number -IsOffline $true
Start-Sleep -Seconds 2
$state = Get-Disk -Number $disk.Number
$state | Select-Object Number, FriendlyName, OperationalStatus, IsOffline, IsReadOnly |
    Format-List |
    Out-String |
    Tee-Object -FilePath $LogPath -Append
if (-not $state.IsOffline) {
    throw 'Disk did not go offline'
}

"EJECT_DONE $(Get-Date -Format o)" | Tee-Object -FilePath $LogPath -Append

