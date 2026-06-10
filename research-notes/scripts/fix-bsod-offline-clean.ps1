param(
  [Parameter(Mandatory = $true)]
  [string]$WinDrive
)

$ErrorActionPreference = "Stop"
$WinDrive = $WinDrive.TrimEnd("\", ":") + ":"
$WinRoot = Join-Path $WinDrive "Windows"
$WoaRoot = Join-Path $WinDrive "woa"
if (-not (Test-Path -LiteralPath (Join-Path $WinRoot "System32"))) {
  throw "$WinDrive is not the offline Windows partition"
}
if (-not (Test-Path -LiteralPath $WoaRoot)) {
  New-Item -ItemType Directory -Force -Path $WoaRoot | Out-Null
}

$Log = Join-Path $WoaRoot "fix-bsod-offline.log"
function Write-Log {
  param([string]$Message)
  $line = "{0}  {1}" -f (Get-Date).ToString("HH:mm:ss"), $Message
  $line | Tee-Object -FilePath $Log -Append
}

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  Write-Log "FATAL: run this script from an elevated PowerShell/CMD."
  exit 740
}

$bad = @(
  "qcpmic",
  "qcppx",
  "qcpil",
  "pilc",
  "qcpep",
  "qcscm",
  "qcsmmu",
  "qciommu",
  "qcspmi"
)

Write-Log "=== Offline BSOD 0xA0 driver cleanup for image $WinDrive ==="
Write-Log "Enumerating third-party drivers"
$list = & dism.exe /English /Image:$WinDrive /Get-Drivers /Format:List 2>&1
$list | Out-File -FilePath $Log -Append -Encoding utf8

$items = New-Object System.Collections.Generic.List[object]
$published = $null
$original = $null
foreach ($line in $list) {
  if ($line -match "Published Name\s*:\s*(oem\d+\.inf)") {
    $published = $Matches[1]
  }
  if ($line -match "Original File Name\s*:\s*(.+\.inf)") {
    $original = $Matches[1].Trim()
  }
  if ($published -and $original) {
    foreach ($needle in $bad) {
      if ($original.ToLowerInvariant().Contains($needle)) {
        $items.Add([pscustomobject]@{
          Published = $published
          Original = $original
          Match = $needle
        })
        break
      }
    }
    $published = $null
    $original = $null
  }
}

if ($items.Count -eq 0) {
  Write-Log "No matching bad third-party driver packages found."
} else {
  Write-Log ("Removing {0} bad driver package(s)" -f $items.Count)
}

$removed = 0
$failed = 0
foreach ($item in $items) {
  Write-Log ("REMOVE {0} original={1} match={2}" -f $item.Published, $item.Original, $item.Match)
  $out = & dism.exe /English /Image:$WinDrive /Remove-Driver /Driver:$($item.Published) 2>&1
  $out | Out-File -FilePath $Log -Append -Encoding utf8
  if (($LASTEXITCODE -eq 0) -or (($out -join "`n") -match "completed successfully")) {
    $removed++
    Write-Log "  OK"
  } else {
    $failed++
    Write-Log ("  FAILED exit={0}" -f $LASTEXITCODE)
  }
}

Write-Log ("=== Done. removed={0} failed={1} ===" -f $removed, $failed)
exit ([int]($failed -gt 0))

