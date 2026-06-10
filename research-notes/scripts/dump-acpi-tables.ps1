param(
  [string]$OutDir = "C:\woa\acpi-dump"
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$Log = Join-Path $OutDir "acpi-dump.log"
$Summary = Join-Path $OutDir "acpi-summary.txt"
Remove-Item -LiteralPath $Log,$Summary -Force -ErrorAction SilentlyContinue

function Log {
  param([string]$Message)
  $line = "{0}  {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $Message
  $line | Tee-Object -FilePath $Log -Append
}

$source = @"
using System;
using System.Runtime.InteropServices;

public static class FirmwareTables {
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern UInt32 EnumSystemFirmwareTables(UInt32 provider, IntPtr buffer, UInt32 size);

  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern UInt32 GetSystemFirmwareTable(UInt32 provider, UInt32 tableId, IntPtr buffer, UInt32 size);
}
"@
Add-Type -TypeDefinition $source

function U32LE([string]$s) {
  $bytes = [Text.Encoding]::ASCII.GetBytes($s)
  if ($bytes.Length -ne 4) { throw "Signature must be 4 chars: $s" }
  return [BitConverter]::ToUInt32($bytes, 0)
}

function U32BE([string]$s) {
  $bytes = [Text.Encoding]::ASCII.GetBytes($s)
  if ($bytes.Length -ne 4) { throw "Signature must be 4 chars: $s" }
  return ([uint32]$bytes[0] -shl 24) -bor ([uint32]$bytes[1] -shl 16) -bor ([uint32]$bytes[2] -shl 8) -bor [uint32]$bytes[3]
}

function SigFromId([uint32]$id) {
  $bytes = [BitConverter]::GetBytes($id)
  return ([Text.Encoding]::ASCII.GetString($bytes) -replace '[^\x20-\x7e]', '_').Trim()
}

function SigFromData([byte[]]$data) {
  if ($data.Length -lt 4) { return "____" }
  return ([Text.Encoding]::ASCII.GetString($data, 0, 4) -replace '[^\x20-\x7e]', '_').Trim()
}

function ExtractAsciiStrings([byte[]]$data, [int]$minLen = 4) {
  $results = New-Object System.Collections.Generic.List[string]
  $buf = New-Object System.Collections.Generic.List[byte]
  foreach ($byte in $data) {
    if ($byte -ge 32 -and $byte -le 126) {
      $buf.Add($byte)
    } else {
      if ($buf.Count -ge $minLen) {
        $results.Add([Text.Encoding]::ASCII.GetString($buf.ToArray()))
      }
      $buf.Clear()
    }
  }
  if ($buf.Count -ge $minLen) {
    $results.Add([Text.Encoding]::ASCII.GetString($buf.ToArray()))
  }
  return $results
}

function Add-Summary {
  param([string]$Line)
  Add-Content -Encoding utf8 -Path $Summary -Value $Line
}

$provider = U32BE "ACPI"
$terms = @(
  "QCOM", "NTTS", "NVT", "NTP", "NT36", "TOUCH", "TPL",
  "I2C", "GPIO", "PMIC", "VREG", "LPXC", "PEP",
  "GFX", "GPU", "ADRENO", "KBD", "NANOSIC", "PEN",
  "UART", "SPI", "QCOM050B", "QCOM0527", "QCOM052E", "QCOM052F", "QCOM0530"
)

Log "=== ACPI firmware table dump v2 ==="
Log ("Provider ACPI=0x{0:X8}" -f $provider)

$ids = New-Object System.Collections.Generic.List[uint32]
$needed = [FirmwareTables]::EnumSystemFirmwareTables($provider, [IntPtr]::Zero, 0)
if ($needed -gt 0) {
  $ptr = [Runtime.InteropServices.Marshal]::AllocHGlobal([int]$needed)
  try {
    $got = [FirmwareTables]::EnumSystemFirmwareTables($provider, $ptr, $needed)
    $bytes = New-Object byte[] $got
    [Runtime.InteropServices.Marshal]::Copy($ptr, $bytes, 0, [int]$got)
  } finally {
    [Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)
  }
  for ($i = 0; $i -lt $bytes.Length; $i += 4) {
    $ids.Add([BitConverter]::ToUInt32($bytes, $i))
  }
}

$manual = @(
  "DSDT", "SSDT", "FACS", "FACP", "APIC", "GTDT", "BGRT",
  "XSDT", "RSDT", "DBG2", "SPCR", "PPTT", "TPM2", "IORT",
  "MCFG", "CSRT", "FPDT", "UEFI", "WAET", "WPBT"
)
foreach ($sig in $manual) {
  $ids.Add((U32LE $sig))
  $ids.Add((U32BE $sig))
}

$ids = @($ids | Sort-Object -Unique)
Add-Summary ("ACPI ids to try: {0}" -f $ids.Count)

$seenHashes = @{}
$dumped = 0
foreach ($id in $ids) {
  $enumSig = SigFromId $id
  $size = [FirmwareTables]::GetSystemFirmwareTable($provider, $id, [IntPtr]::Zero, 0)
  if ($size -eq 0) {
    $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    Log ("MISS id=0x{0:X8} enumSig={1} err={2}" -f $id, $enumSig, $err)
    continue
  }

  $buf = [Runtime.InteropServices.Marshal]::AllocHGlobal([int]$size)
  try {
    $read = [FirmwareTables]::GetSystemFirmwareTable($provider, $id, $buf, $size)
    if ($read -eq 0) {
      $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
      Log ("FAIL id=0x{0:X8} enumSig={1} err={2}" -f $id, $enumSig, $err)
      continue
    }
    $data = New-Object byte[] $read
    [Runtime.InteropServices.Marshal]::Copy($buf, $data, 0, [int]$read)
  } finally {
    [Runtime.InteropServices.Marshal]::FreeHGlobal($buf)
  }

  $sha = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($data)).Replace("-", "")
  if ($seenHashes.ContainsKey($sha)) {
    Log ("DUP id=0x{0:X8} enumSig={1} sameAs={2}" -f $id, $enumSig, $seenHashes[$sha])
    continue
  }

  $actualSig = SigFromData $data
  $shortSha = $sha.Substring(0, 12)
  $safe = ("{0}-{1}-id{2:X8}-{3}.bin" -f $actualSig, $enumSig, $id, $shortSha) -replace '[^A-Za-z0-9_.-]', '_'
  [IO.File]::WriteAllBytes((Join-Path $OutDir $safe), $data)
  $seenHashes[$sha] = $safe
  $dumped++

  Log ("DUMP actual={0} enumSig={1} id=0x{2:X8} size={3} -> {4}" -f $actualSig, $enumSig, $id, $data.Length, $safe)
  Add-Summary ""
  Add-Summary ("[{0}] enumSig={1} id=0x{2:X8} size={3} file={4}" -f $actualSig, $enumSig, $id, $data.Length, $safe)

  $strings = ExtractAsciiStrings $data 4
  $hits = foreach ($s in $strings) {
    foreach ($term in $terms) {
      if ($s.IndexOf($term, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        $s
        break
      }
    }
  }
  $hits = @($hits | Select-Object -Unique)
  if ($hits.Count -eq 0) {
    Add-Summary "  no interesting strings"
  } else {
    foreach ($hit in $hits) {
      Add-Summary ("  " + $hit)
    }
  }
}

Add-Summary ""
Add-Summary ("Dumped unique tables: {0}" -f $dumped)
Log ("Dumped unique tables: {0}" -f $dumped)
Log "Wrote $Summary"
Log "=== done ==="

