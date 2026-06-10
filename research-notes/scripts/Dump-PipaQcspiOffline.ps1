param(
    [string] $WinDrive = 'E',
    [string] $OutRoot = '',
    [string] $LogPath = '<ARTIFACT_DIR>\dump-qcspi-offline-20260605.log'
)

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $argList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', "`"$PSCommandPath`"",
        '-WinDrive', $WinDrive,
        '-OutRoot', "`"$OutRoot`"",
        '-LogPath', "`"$LogPath`""
    ) -join ' '
    Start-Process powershell.exe -Verb RunAs -ArgumentList $argList -Wait
    exit
}

function Log {
    param([string] $Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $line | Tee-Object -FilePath $LogPath -Append
}

function Copy-IfExists {
    param([string] $Source, [string] $Destination)
    if (Test-Path -LiteralPath $Source) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
        Log "Copied $Source"
    }
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath) | Out-Null
"=== PIPA QCSPI OFFLINE DUMP START $(Get-Date -Format o) ===" |
    Set-Content -LiteralPath $LogPath -Encoding UTF8

$driveRoot = "$($WinDrive.TrimEnd(':')):\"
$volume = Get-Volume -DriveLetter $WinDrive.TrimEnd(':')
if ($volume.FileSystemLabel -ne 'WINPIPA' -or $volume.FileSystem -ne 'NTFS') {
    throw "$driveRoot is not WINPIPA NTFS."
}
if ($volume.Size -lt 60GB -or $volume.Size -gt 75GB) {
    throw "$driveRoot size safety check failed: $($volume.Size)."
}

if (-not $OutRoot) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutRoot = Join-Path (Get-Location) "qcspi-offline-dump-$stamp"
}
New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null
Log "Dump root: $OutRoot"
Log "Verified $driveRoot as WINPIPA."

$summary = New-Object System.Collections.Generic.List[string]
$summary.Add("Pipa QCSPI offline dump")
$summary.Add("Timestamp: $(Get-Date -Format o)")
$summary.Add("WinDrive: $driveRoot")
$summary.Add("")

Copy-IfExists (Join-Path $driveRoot 'Windows\INF\setupapi.dev.log') (Join-Path $OutRoot 'logs\setupapi.dev.log')
Copy-IfExists (Join-Path $driveRoot 'Windows\INF\setupapi.setup.log') (Join-Path $OutRoot 'logs\setupapi.setup.log')
Copy-IfExists (Join-Path $driveRoot 'Windows\System32\winevt\Logs\System.evtx') (Join-Path $OutRoot 'eventlogs\System.evtx')
Copy-IfExists (Join-Path $driveRoot 'Windows\System32\winevt\Logs\Application.evtx') (Join-Path $OutRoot 'eventlogs\Application.evtx')
Copy-IfExists (Join-Path $driveRoot 'Windows\System32\winevt\Logs\Microsoft-Windows-Kernel-PnP%4Configuration.evtx') (Join-Path $OutRoot 'eventlogs\Kernel-PnP-Configuration.evtx')
Copy-IfExists (Join-Path $driveRoot 'Windows\System32\winevt\Logs\Microsoft-Windows-DriverFrameworks-UserMode%4Operational.evtx') (Join-Path $OutRoot 'eventlogs\DriverFrameworks-UserMode-Operational.evtx')

$minidump = Join-Path $driveRoot 'Windows\Minidump'
if (Test-Path -LiteralPath $minidump) {
    Copy-Item -LiteralPath $minidump -Destination (Join-Path $OutRoot 'Minidump') -Recurse -Force
    Log 'Copied Minidump directory.'
}
$liveKernel = Join-Path $driveRoot 'Windows\LiveKernelReports'
if (Test-Path -LiteralPath $liveKernel) {
    Copy-Item -LiteralPath $liveKernel -Destination (Join-Path $OutRoot 'LiveKernelReports') -Recurse -Force
    Log 'Copied LiveKernelReports directory.'
}

$infRoot = Join-Path $OutRoot 'matching-infs'
New-Item -ItemType Directory -Force -Path $infRoot | Out-Null
$patterns = 'qcspi|qcgpi|qcsmmu|qcpep|qcppx|qcpil|qcpmic|QCOM050F|QCOM0593|QCOM250F|QCOM0D0A|QCOM0C'
$matchingInfs = @(Get-ChildItem -LiteralPath (Join-Path $driveRoot 'Windows\INF') -Filter '*.inf' -ErrorAction SilentlyContinue |
    Where-Object {
        $text = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue
        $text -match $patterns
    })
foreach ($inf in $matchingInfs) {
    Copy-Item -LiteralPath $inf.FullName -Destination (Join-Path $infRoot $inf.Name) -Force
}
$matchingInfs | Select-Object Name,Length,LastWriteTime |
    Export-Csv -LiteralPath (Join-Path $OutRoot 'matching-infs.csv') -NoTypeInformation
$summary.Add("Matching INF count: $($matchingInfs.Count)")

$setupapi = Join-Path $driveRoot 'Windows\INF\setupapi.dev.log'
if (Test-Path -LiteralPath $setupapi) {
    $lines = Get-Content -LiteralPath $setupapi -Encoding Default -ErrorAction SilentlyContinue
    $hits = for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $patterns) {
            $start = [Math]::Max(0, $i - 5)
            $end = [Math]::Min($lines.Count - 1, $i + 12)
            "---- setupapi lines {0}-{1} ----" -f ($start + 1), ($end + 1)
            for ($j = $start; $j -le $end; $j++) { "{0}: {1}" -f ($j + 1), $lines[$j] }
        }
    }
    $hits | Set-Content -LiteralPath (Join-Path $OutRoot 'setupapi-relevant-snippets.txt') -Encoding UTF8
}

$hive = 'HKLM\PIPA_DUMP_SYSTEM'
$systemHive = Join-Path $driveRoot 'Windows\System32\config\SYSTEM'
$loaded = $false
try {
    & reg.exe load $hive $systemHive 2>&1 | Tee-Object -FilePath $LogPath -Append
    $loaded = $true

    foreach ($key in @(
        "$hive\ControlSet001\Enum\ACPI",
        "$hive\ControlSet001\Services",
        "$hive\ControlSet001\Control\Class"
    )) {
        $name = ($key -replace '^HKLM\\PIPA_DUMP_SYSTEM\\ControlSet001\\','') -replace '[\\/:*?"<>|]', '_'
        & reg.exe export $key (Join-Path $OutRoot "registry-$name.reg") /y 2>&1 |
            Tee-Object -FilePath $LogPath -Append
    }

    $serviceDump = Join-Path $OutRoot 'services-relevant.txt'
    foreach ($service in @('qcspi','qcgpi','qcGPI','qcpep','qcsmmu','qciommu','qcppx','qcpil','qcpmic','qcpmicgpio','qcdx8250','qdcmlib')) {
        "===== $service =====" | Add-Content -LiteralPath $serviceDump
        foreach ($cs in @('ControlSet001','ControlSet002')) {
            & reg.exe query "$hive\$cs\Services\$service" /s 2>&1 |
                Add-Content -LiteralPath $serviceDump
        }
    }

    $enumDump = Join-Path $OutRoot 'enum-acpi-relevant.txt'
    $enumText = & reg.exe query "$hive\ControlSet001\Enum\ACPI" /s 2>&1
    $enumText | Select-String -Pattern 'QCOM050F|QCOM0593|QCOM250F|QCOM0D|QCOM0C|PEP|MMU|GPI|SPI|NVT|NTTS' -Context 0,8 |
        ForEach-Object {
            $_.Line
            $_.Context.PostContext
            ''
        } | Set-Content -LiteralPath $enumDump -Encoding UTF8
} finally {
    if ($loaded) {
        [gc]::Collect()
        Start-Sleep -Milliseconds 500
        & reg.exe unload $hive 2>&1 | Tee-Object -FilePath $LogPath -Append
    }
}

$summary.Add("QCSPI startup exists: $(Test-Path -LiteralPath (Join-Path $driveRoot 'ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\Codex-QCSPI-Only.cmd'))")
$summary.Add("Pad5 SPI startup exists: $(Test-Path -LiteralPath (Join-Path $driveRoot 'ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\Codex-Pad5-SPI-Only.cmd'))")
$summary.Add("QCSPI DONE exists: $(Test-Path -LiteralPath (Join-Path $driveRoot 'woa\qcspi-only\DONE.txt'))")
$summary.Add("Pad5 SPI DONE exists: $(Test-Path -LiteralPath (Join-Path $driveRoot 'woa\pad5-spi-only\DONE.txt'))")
$summary.Add("Minidump count: $(@(Get-ChildItem -LiteralPath (Join-Path $OutRoot 'Minidump') -File -Recurse -ErrorAction SilentlyContinue).Count)")
$summary.Add("LiveKernelReports count: $(@(Get-ChildItem -LiteralPath (Join-Path $OutRoot 'LiveKernelReports') -File -Recurse -ErrorAction SilentlyContinue).Count)")
$summary | Set-Content -LiteralPath (Join-Path $OutRoot 'SUMMARY.txt') -Encoding UTF8

Log 'QCSPI_OFFLINE_DUMP_DONE'
"=== PIPA QCSPI OFFLINE DUMP END $(Get-Date -Format o) ===" |
    Add-Content -LiteralPath $LogPath
Write-Output "DUMP_ROOT=$OutRoot"

