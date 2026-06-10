$ErrorActionPreference = "Continue"

$Root = "C:\woa\i2c-trace-v1"
$Result = Join-Path $Root "RESULT.txt"
$Done = Join-Path $Root "DONE.txt"
$Transcript = Join-Path $Root "transcript.txt"
$LogDir = "C:\Renegade\Logfiles"
$TraceName = "PipaI2CTrace"
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$EtlPath = Join-Path $LogDir ("PipaI2CTrace-{0}.etl" -f $Stamp)

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Add-Line {
    param([string]$Text)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Text
    $line | Tee-Object -FilePath $Result -Append
}

function Run-Cmd {
    param(
        [string]$Label,
        [string]$File,
        [string[]]$ArgList
    )
    Add-Line ("RUN {0}: {1} {2}" -f $Label, $File, ($ArgList -join " "))
    try {
        & $File @ArgList 2>&1 | Tee-Object -FilePath $Result -Append
        $code = $LASTEXITCODE
        Add-Line ("EXIT {0}: {1}" -f $Label, $code)
        return $code
    }
    catch {
        Add-Line ("ERROR {0}: {1}" -f $Label, $_.Exception.Message)
        return -1
    }
}

function Remove-StartupFallback {
    $paths = @(
        (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup\Pipa-I2C-Trace.cmd"),
        (Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\Startup\Pipa-I2C-Trace.cmd")
    )
    foreach ($path in $paths) {
        if (Test-Path -LiteralPath $path) {
            try {
                Remove-Item -LiteralPath $path -Force
                Add-Line ("Removed startup fallback {0}" -f $path)
            }
            catch {
                Add-Line ("Could not remove startup fallback {0}: {1}" -f $path, $_.Exception.Message)
            }
        }
    }
}

function Dump-Instance {
    param([string]$InstanceId)
    "--- pnputil $InstanceId ---" | Tee-Object -FilePath $Result -Append
    Run-Cmd "pnputil $InstanceId" "pnputil.exe" @("/enum-devices", "/instanceid", $InstanceId, "/drivers", "/resources") | Out-Null
    "--- Get-PnpDevice $InstanceId ---" | Tee-Object -FilePath $Result -Append
    try {
        Get-PnpDevice -InstanceId $InstanceId -ErrorAction SilentlyContinue |
            Format-List * | Out-String -Width 220 |
            Tee-Object -FilePath $Result -Append
    }
    catch {
        Add-Line ("Get-PnpDevice failed for {0}: {1}" -f $InstanceId, $_.Exception.Message)
    }
}

function Dump-State {
    param([string]$Name)
    "=== STATE $Name ===" | Tee-Object -FilePath $Result -Append
    foreach ($id in @(
        "ACPI\QCOM0511\2",
        "ACPI\QCOM050D\0",
        "ACPI\QCOM0593\0",
        "ACPI\QCOM0519\2&daba3ff&0",
        "ACPI\QCOM050F\4"
    )) {
        Dump-Instance $id
    }
    foreach ($svc in @("qci2c", "qcgpio", "qcgpi", "qcpep", "qcspi")) {
        "--- service $svc ---" | Tee-Object -FilePath $Result -Append
        Run-Cmd "service $svc" "sc.exe" @("query", $svc) | Out-Null
    }
}

New-Item -ItemType Directory -Force -Path $Root, $LogDir | Out-Null
if (Test-Path -LiteralPath $Result) {
    Rename-Item -LiteralPath $Result -NewName ("RESULT-{0}.bak.txt" -f $Stamp) -Force -ErrorAction SilentlyContinue
}
Start-Transcript -Path $Transcript -Append | Out-Null

Add-Line ("=== PIPA I2C TRACE V1 START {0} ===" -f (Get-Date -Format o))
Add-Line ("Running as {0}" -f ([Security.Principal.WindowsIdentity]::GetCurrent().Name))

Remove-StartupFallback

if (-not (Test-Admin)) {
    Add-Line "Not elevated. Requesting UAC for I2C trace."
    $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
    Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $args
    Add-Line "Spawned elevated process; exiting non-elevated launcher."
    Stop-Transcript | Out-Null
    exit 0
}

$Providers = @(
    "166ca27c-7967-3f96-44b1-966621ed397d",
    "185db63e-5c8f-32d4-81fe-f6ea634c719b",
    "45900a2c-0b94-3c9d-aa85-584db03ceb3b",
    "500c3aa6-6ed0-3b11-40fb-7aca8da1c07c",
    "519f6260-722c-37cb-9f18-f881e23c803e",
    "7200fdf5-fba9-3160-fe81-6708d481fcbc",
    "7d38832a-c05b-35e7-0fb6-ebd01486c07b",
    "946f2c41-487c-302d-a0d1-f8716241bb4f",
    "9e00f575-cb76-3e77-b996-26722efbca3d",
    "a658792c-32a3-312a-ee99-9af9a942469b",
    "db114eb5-b43b-34d3-50d8-6e6ca95ce955",
    "ea364299-8c8d-3cf2-60e8-b08df12c161a",
    "fc96a0ef-e5c0-3fa5-9e9f-c2ab78e27431",
    "fdd10c02-75dd-3574-63eb-098872651f50",
    "08409c29-bfc5-35dd-781d-d58eda82c272",
    "0f9dc4fb-4c4f-38fa-d576-ea4b13bd46e8",
    "03594d7d-7e2a-33b4-e0c1-2cf8051e785e",
    "0e685e04-298a-39a7-9be4-7fa70e695713",
    "0f93d166-1889-320f-f80b-cfccbc93d7e5",
    "434b457e-0fde-3d22-bf58-24563bfba2b8",
    "ae7d9bf8-79ef-3ab1-e7f8-3102edb58b99",
    "b2e40968-0f8b-3639-44e0-c43869970e9d",
    "0df78e97-e6d0-3e08-cabe-b4347752ad2c",
    "078c203a-4feb-3950-58bd-c3a280953870"
)

Run-Cmd "stop old trace" "logman.exe" @("stop", $TraceName, "-ets") | Out-Null
Run-Cmd "delete old trace" "logman.exe" @("delete", $TraceName) | Out-Null
Run-Cmd "create trace" "logman.exe" @("create", "trace", $TraceName, "-o", $EtlPath, "-f", "bincirc", "-max", "256", "-nb", "16", "128", "-bs", "1024", "-ets") | Out-Null
foreach ($provider in $Providers) {
    Run-Cmd "provider $provider" "logman.exe" @("update", "trace", $TraceName, "-p", "{${provider}}", "0xFFFFFFFF", "0xFF", "-ets") | Out-Null
}
Run-Cmd "query trace" "logman.exe" @("query", $TraceName, "-ets") | Out-Null

Dump-State "BEFORE_QCI2C_RESTART"

Add-Line "Restarting ACPI\QCOM0511\2 once. No driver install is performed."
Run-Cmd "restart QCOM0511" "pnputil.exe" @("/restart-device", "ACPI\QCOM0511\2") | Out-Null
Start-Sleep -Seconds 8

Dump-State "AFTER_QCI2C_RESTART"

Run-Cmd "stop trace" "logman.exe" @("stop", $TraceName, "-ets") | Out-Null
Add-Line ("TRACE_ETL={0}" -f $EtlPath)
Add-Line ("=== PIPA I2C TRACE V1 END {0} ===" -f (Get-Date -Format o))
Set-Content -LiteralPath $Done -Value ("DONE {0}" -f (Get-Date -Format o)) -Encoding ASCII
Stop-Transcript | Out-Null

