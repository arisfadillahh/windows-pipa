param(
    [switch]$NoAutoShutdown
)

$ErrorActionPreference = "Continue"
$Root = "C:\woa"
$RunDir = Join-Path $Root "spi-kona-run"
$PhaseFile = Join-Path $RunDir "phase1.done"
$FinalFile = Join-Path $RunDir "DONE.txt"
$LogFile = Join-Path $RunDir "install-spi-kona.log"
$StartupCmd = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup\install-spi-kona.cmd"
$GlobalStartupCmd = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\Startup\install-spi-kona.cmd"
$GpoStartupCmd = Join-Path $env:SystemRoot "System32\GroupPolicy\Machine\Scripts\Startup\codex-spi-kona.cmd"
$GpoScriptsIni = Join-Path $env:SystemRoot "System32\GroupPolicy\Machine\Scripts\scripts.ini"

function Ensure-Dir($Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Log($Message) {
    Ensure-Dir $RunDir
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"), $Message
    $line | Tee-Object -FilePath $LogFile -Append
}

function Run-Logged($File, [string[]]$RunArgs) {
    Log ("RUN: {0} {1}" -f $File, ($RunArgs -join " "))
    & $File @RunArgs 2>&1 | Tee-Object -FilePath $LogFile -Append
    $code = $LASTEXITCODE
    Log ("EXIT: {0}" -f $code)
    return $code
}

function Dump-Status($Name) {
    $OutDir = Join-Path $RunDir $Name
    Ensure-Dir $OutDir
    Log "Dumping status to $OutDir"

    cmd /c "pnputil /enum-devices /connected /ids /drivers > `"$OutDir\pnputil-connected.txt`" 2>&1"
    cmd /c "pnputil /enum-devices /ids /drivers > `"$OutDir\pnputil-all.txt`" 2>&1"
    cmd /c "pnputil /enum-devices /problem /ids /drivers > `"$OutDir\pnputil-problem.txt`" 2>&1"
    Get-PnpDevice | Format-List Status,Class,FriendlyName,InstanceId,Problem |
        Out-File -FilePath (Join-Path $OutDir "get-pnp-all.txt") -Encoding utf8
    Get-PnpDevice -PresentOnly | Format-List Status,Class,FriendlyName,InstanceId,Problem |
        Out-File -FilePath (Join-Path $OutDir "get-pnp-present.txt") -Encoding utf8
    Get-CimInstance Win32_PnPEntity |
        Select-Object Status,PNPClass,Name,DeviceID,ConfigManagerErrorCode,Service |
        Export-Csv -NoTypeInformation -Path (Join-Path $OutDir "cim-pnp.csv")
    cmd /c "sc.exe query type= driver state= all > `"$OutDir\driver-services.txt`" 2>&1"

    $Needles = "QCOM050F|QCOM0593|QCOM050D|NVT36532|NTTS3652|NTP36532|nt36|qcspi|Nanosic|VID_2717|VID_258A|BasicDisplay|Problem|0xC0000490|CM_PROB"
    Select-String -Path (Join-Path $OutDir "*") -Pattern $Needles -CaseSensitive:$false |
        Out-File -FilePath (Join-Path $OutDir "interesting-hits.txt") -Encoding utf8
}

function Get-PublishedDriversByOriginalName([string[]]$OriginalNames) {
    $drivers = pnputil /enum-drivers 2>&1
    $items = @()
    $current = @{}
    foreach ($line in $drivers) {
        if ($line -match "^\s*$") { continue }
        if ($line -match "Published Name\s*:\s*(.+)$") {
            if ($current.Count -gt 0) {
                $items += [pscustomobject]$current
            }
            $current = @{ PublishedName = $matches[1].Trim() }
            continue
        }
        if ($line -match "Original Name\s*:\s*(.+)$") {
            $current.OriginalName = $matches[1].Trim()
            continue
        }
    }
    if ($current.Count -gt 0) {
        $items += [pscustomobject]$current
    }
    $items | Where-Object { $OriginalNames -contains $_.OriginalName }
}

Ensure-Dir $RunDir

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).
    IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Log "Not elevated. Requesting UAC."
    $args = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($NoAutoShutdown) {
        $args += " -NoAutoShutdown"
    }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $args -Wait
    Log "Elevated process returned."
    exit 0
}

Start-Transcript -Path (Join-Path $RunDir "transcript.log") -Append | Out-Null
Log "install-spi-kona start. Admin=$isAdmin"

if (-not (Test-Path -LiteralPath $PhaseFile)) {
    Log "PHASE1: install Kona SPI candidate and stage touch driver."
    Dump-Status "before-install"

    Run-Logged "bcdedit.exe" @("/set", "testsigning", "on") | Out-Null

    $oldDrivers = Get-PublishedDriversByOriginalName @("mipad5_spi.inf")
    foreach ($driver in $oldDrivers) {
        Log ("Deleting old SPI driver {0} ({1})" -f $driver.PublishedName, $driver.OriginalName)
        Run-Logged "pnputil.exe" @("/delete-driver", $driver.PublishedName, "/uninstall", "/force") | Out-Null
    }

    $spiInf = Join-Path $Root "spi-kona-pipa\qcspi8250-pipa.inf"
    if (Test-Path -LiteralPath $spiInf) {
        Run-Logged "pnputil.exe" @("/add-driver", $spiInf, "/install") | Out-Null
    } else {
        Log "MISSING: $spiInf"
    }

    $touchInf = Join-Path $Root "touch-chain-drivers\Touch\nt36xxx.inf"
    if (Test-Path -LiteralPath $touchInf) {
        Run-Logged "pnputil.exe" @("/add-driver", $touchInf, "/install") | Out-Null
    } else {
        Log "MISSING: $touchInf"
    }

    Run-Logged "pnputil.exe" @("/restart-device", "ACPI\QCOM050F\4") | Out-Null
    Dump-Status "after-install-before-reboot"

    "phase1 complete at $(Get-Date -Format o)" | Out-File -FilePath $PhaseFile -Encoding ascii
    Log "PHASE1 complete. Rebooting Windows in 15 seconds for post-reboot dump."
    shutdown.exe /r /f /t 15 /c "Codex SPI Kona phase 1 complete. Rebooting for driver status dump."
    Stop-Transcript | Out-Null
    exit 0
}

Log "PHASE2: post-reboot dump and cleanup."
Dump-Status ("post-reboot-" + (Get-Date -Format "yyyyMMdd-HHmmss"))

if (Test-Path -LiteralPath $StartupCmd) {
    Remove-Item -LiteralPath $StartupCmd -Force
    Log "Removed Startup autorun: $StartupCmd"
}
if (Test-Path -LiteralPath $GlobalStartupCmd) {
    Remove-Item -LiteralPath $GlobalStartupCmd -Force
    Log "Removed global Startup autorun: $GlobalStartupCmd"
}
if (Test-Path -LiteralPath $GpoStartupCmd) {
    Remove-Item -LiteralPath $GpoStartupCmd -Force
    Log "Removed GPO startup script: $GpoStartupCmd"
}
if (Test-Path -LiteralPath $GpoScriptsIni) {
    $gpoText = Get-Content -LiteralPath $GpoScriptsIni -Raw -ErrorAction SilentlyContinue
    if ($gpoText -match "codex-spi-kona\.cmd") {
        "[Startup]`r`n" | Out-File -FilePath $GpoScriptsIni -Encoding ascii
        Log "Cleared Codex entry from GPO scripts.ini: $GpoScriptsIni"
    }
}

"DONE: install-spi-kona post-reboot dump complete at $(Get-Date -Format o)" |
    Out-File -FilePath $FinalFile -Encoding ascii
Log "PHASE2 complete."

if (-not $NoAutoShutdown) {
    Log "Scheduling full shutdown in 45 seconds so WINPIPA is clean for offline reads."
    shutdown.exe /s /f /t 45 /c "Codex SPI Kona dump complete. Full shutdown keeps WINPIPA clean."
}

Stop-Transcript | Out-Null

