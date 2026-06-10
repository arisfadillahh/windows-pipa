param(
    [string]$WinDrive = "E:"
)

$ErrorActionPreference = "Continue"
$ProjectRoot = "<PROJECT_ROOT>"
$HostLogDir = Join-Path $ProjectRoot "logs\host-stage-spi-kona"
$HostLog = Join-Path $HostLogDir ("stage-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
$Hive = "HKLM\PIPA_SOFTWARE"

function Ensure-Dir($Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Log($Message) {
    Ensure-Dir $HostLogDir
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"), $Message
    $line | Tee-Object -FilePath $HostLog -Append
}

function Run-Logged($File, [string[]]$RunArgs) {
    Log ("RUN: {0} {1}" -f $File, ($RunArgs -join " "))
    & $File @RunArgs 2>&1 | Tee-Object -FilePath $HostLog -Append
    $code = $LASTEXITCODE
    Log ("EXIT: {0}" -f $code)
    return $code
}

Ensure-Dir $HostLogDir
Log "Host elevated stage start. WinDrive=$WinDrive"

$ImagePath = $WinDrive.TrimEnd("\") + "\"
$Woa = Join-Path $WinDrive "woa"
$SpiInf = Join-Path $Woa "spi-kona-pipa\qcspi8250-pipa.inf"
$TouchInf = Join-Path $Woa "touch-chain-drivers\Touch\nt36xxx.inf"

if (-not (Test-Path -LiteralPath $SpiInf)) {
    Log "MISSING: $SpiInf"
    exit 2
}

Run-Logged "dism.exe" @("/Image:$ImagePath", "/Get-Drivers", "/Format:List") | Out-Null

$driverList = dism.exe /Image:$ImagePath /Get-Drivers /Format:List 2>&1
$driverList | Out-File -FilePath (Join-Path $HostLogDir "drivers-before.txt") -Encoding utf8
$blocks = ($driverList -join "`n") -split "(\r?\n){2,}"
foreach ($block in $blocks) {
    if ($block -match "Published Name\s*:\s*(oem\d+\.inf)" -and $block -match "Original File Name\s*:\s*mipad5_spi\.inf") {
        $pub = $matches[1]
        Log "Removing old MiPad5 SPI offline driver: $pub"
        Run-Logged "dism.exe" @("/Image:$ImagePath", "/Remove-Driver", "/Driver:$pub") | Out-Null
    }
}

Run-Logged "dism.exe" @("/Image:$ImagePath", "/Add-Driver", "/Driver:$SpiInf", "/ForceUnsigned") | Out-Null
if (Test-Path -LiteralPath $TouchInf) {
    Run-Logged "dism.exe" @("/Image:$ImagePath", "/Add-Driver", "/Driver:$TouchInf", "/ForceUnsigned") | Out-Null
} else {
    Log "Touch INF missing, skip: $TouchInf"
}

Run-Logged "dism.exe" @("/Image:$ImagePath", "/Get-Drivers", "/Format:List") | Out-Null

reg.exe unload $Hive 2>$null | Out-Null
$SoftwareHive = Join-Path $WinDrive "Windows\System32\config\SOFTWARE"
Run-Logged "reg.exe" @("load", $Hive, $SoftwareHive) | Out-Null
Run-Logged "reg.exe" @("add", "$Hive\Microsoft\Windows\CurrentVersion\RunOnce", "/v", "CodexSpiDump", "/t", "REG_SZ", "/d", "C:\woa\dump-spi-status.cmd", "/f") | Out-Null
Run-Logged "reg.exe" @("query", "$Hive\Microsoft\Windows\CurrentVersion\RunOnce", "/v", "CodexSpiDump") | Out-Null
Run-Logged "reg.exe" @("unload", $Hive) | Out-Null

Log "Stage complete. It is safe to boot tablet Windows now."

