param(
    [string]$WinDrive = "F",
    [string]$TraceName = "PipaBootTrace",
    [string]$TmfRoot = "<PROJECT_ROOT>\WOA-Drivers-debug\tmf"
)

$ErrorActionPreference = "Stop"

function Info([string]$Message) {
    Write-Host ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message)
}

$win = "$WinDrive`:"
$systemHive = Join-Path $win "Windows\System32\Config\SYSTEM"
if (!(Test-Path -LiteralPath $systemHive)) {
    throw "SYSTEM hive not found at $systemHive"
}
if (!(Test-Path -LiteralPath $TmfRoot)) {
    throw "TMF directory not found at $TmfRoot"
}

$backupDir = Join-Path $win "woa\offline-reg-backups"
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupHive = Join-Path $backupDir "SYSTEM-before-$TraceName-$stamp"
Copy-Item -LiteralPath $systemHive -Destination $backupHive -Force
Info "Backed up SYSTEM hive to $backupHive"

$patterns = @(
    "^// PDB:\s+qci2c",
    "^// PDB:\s+qcgpio",
    "^// PDB:\s+qcgpi",
    "^// PDB:\s+qcpep"
)

$providers = New-Object System.Collections.Generic.List[string]
Get-ChildItem -LiteralPath $TmfRoot -Filter "*.tmf" | ForEach-Object {
    $head = Get-Content -LiteralPath $_.FullName -TotalCount 1 -ErrorAction SilentlyContinue
    foreach ($pattern in $patterns) {
        if ($head -match $pattern) {
            $providers.Add($_.BaseName.ToLowerInvariant())
            break
        }
    }
}

$providers = $providers | Sort-Object -Unique
if ($providers.Count -eq 0) {
    throw "No matching qci2c/qcgpio/qcgpi/qcpep TMF provider GUIDs found."
}
Info "Provider count: $($providers.Count)"

$loaded = $false
try {
    reg.exe unload HKLM\PIPASYS 2>$null | Out-Null
    reg.exe load HKLM\PIPASYS $systemHive | Out-Null
    $loaded = $true

    $select = Get-ItemProperty -Path "HKLM:\PIPASYS\Select"
    $controlSet = "ControlSet{0:D3}" -f [int]$select.Current
    Info "Using $controlSet"

    $base = "HKLM:\PIPASYS\$controlSet\Control\WMI\Autologger\$TraceName"
    if (Test-Path $base) {
        Remove-Item -Path $base -Recurse -Force
    }
    New-Item -Path $base -Force | Out-Null

    $traceFile = "C:\Renegade\Logfiles\$TraceName.etl"
    New-ItemProperty -Path $base -Name "Start" -PropertyType DWord -Value 1 -Force | Out-Null
    New-ItemProperty -Path $base -Name "Guid" -PropertyType String -Value "{b23a2668-6d11-4d4e-a704-f3a0f6d4a5f8}" -Force | Out-Null
    New-ItemProperty -Path $base -Name "FileName" -PropertyType String -Value $traceFile -Force | Out-Null
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

    $outDir = Join-Path $win "woa\boot-trace-v1"
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $providers | Set-Content -LiteralPath (Join-Path $outDir "providers.txt") -Encoding ASCII
    @(
        "TraceName=$TraceName",
        "TraceFile=$traceFile",
        "OfflineHiveBackup=$backupHive",
        "ControlSet=$controlSet",
        "ProviderCount=$($providers.Count)",
        "ConfiguredAt=$(Get-Date -Format o)"
    ) | Set-Content -LiteralPath (Join-Path $outDir "CONFIGURED.txt") -Encoding ASCII

    Info "Configured offline autologger $TraceName -> $traceFile"
}
finally {
    if ($loaded) {
        [gc]::Collect()
        [gc]::WaitForPendingFinalizers()
        reg.exe unload HKLM\PIPASYS | Out-Null
        Info "Unloaded offline SYSTEM hive"
    }
}

