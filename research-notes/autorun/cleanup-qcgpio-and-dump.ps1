$ErrorActionPreference = "SilentlyContinue"

$OutDir = "C:\woa\cleanup-qcgpio"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Remove-Item -LiteralPath (Join-Path $OutDir "DONE.txt") -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $OutDir "ERROR.txt") -Force -ErrorAction SilentlyContinue

$Result = Join-Path $OutDir "RESULT.txt"

function Add-Line {
    param([string]$Text = "")
    $Text | Add-Content -LiteralPath $Result -Encoding UTF8
}

function Ensure-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $cmd = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        Start-Process -FilePath "powershell.exe" -ArgumentList $cmd -Verb RunAs
        exit
    }
}

function Run-Cmd {
    param(
        [string]$Title,
        [string]$FilePath,
        [string[]]$Arguments = @()
    )
    Add-Line ""
    Add-Line "==== $Title ===="
    Add-Line "RUN $FilePath $($Arguments -join ' ')"
    try {
        & $FilePath @Arguments 2>&1 | ForEach-Object { Add-Line "$_" }
        Add-Line "exit=$LASTEXITCODE"
    }
    catch {
        Add-Line "ERROR: $($_.Exception.Message)"
    }
}

try {
    "Pipa qcgpio cleanup and bus dump" | Set-Content -LiteralPath $Result -Encoding UTF8
    Add-Line "started: $(Get-Date -Format o)"
    Add-Line "user: $env:USERDOMAIN\$env:USERNAME"
    Ensure-Admin
    Add-Line "admin: yes"

    Add-Line ""
    Add-Line "==== before PnP summary ===="
    Get-PnpDevice -PresentOnly |
        Where-Object { $_.InstanceId -match "QCOM050D|QCOM2511|QCOM0511|QCOM0593|QCOM0519|QCOM050F|I2C|GPI" } |
        Sort-Object InstanceId |
        Format-Table -AutoSize Status,Class,FriendlyName,InstanceId,Problem |
        Out-String -Width 240 |
        ForEach-Object { Add-Line $_ }

    Add-Line ""
    Add-Line "==== qcgpio packages before cleanup ===="
    $drivers = pnputil.exe /enum-drivers 2>&1
    $drivers | Select-String -Pattern "Published Name|Original Name|Provider Name|Class Name|Driver Version|qcgpio" -Context 0,4 |
        ForEach-Object { Add-Line "$_" }

    $published = @()
    $text = $drivers -join "`n"
    $blocks = [regex]::Split($text, "(?m)(?=Published Name\s*:)")
    foreach ($block in $blocks) {
        if ($block -match "qcgpio") {
            if ($block -match "Published Name\s*:\s*(oem\d+\.inf)") {
                $published += $matches[1]
            }
        }
    }
    $published = $published | Sort-Object -Unique

    if ($published.Count -eq 0) {
        Add-Line "No qcgpio driver package found."
    }
    else {
        foreach ($inf in $published) {
            Run-Cmd "delete $inf" "pnputil.exe" @("/delete-driver", $inf, "/uninstall", "/force")
        }
    }

    Run-Cmd "scan devices" "pnputil.exe" @("/scan-devices")

    Add-Line ""
    Add-Line "==== after PnP summary ===="
    Get-PnpDevice -PresentOnly |
        Where-Object { $_.InstanceId -match "QCOM050D|QCOM2511|QCOM0511|QCOM0593|QCOM0519|QCOM050F|I2C|GPI" } |
        Sort-Object InstanceId |
        Format-Table -AutoSize Status,Class,FriendlyName,InstanceId,Problem |
        Out-String -Width 240 |
        ForEach-Object { Add-Line $_ }

    foreach ($id in @(
        "ACPI\QCOM050D\0",
        "ACPI\QCOM2511\2",
        "ACPI\QCOM0511\2",
        "ACPI\QCOM0593\0"
    )) {
        Run-Cmd "pnputil full $id" "pnputil.exe" @("/enum-devices", "/instanceid", $id, "/deviceids", "/drivers", "/properties", "/resources")
    }

    Add-Line ""
    Add-Line "If QCOM050D still has Code 12, reboot once and run C:\woa\RUN.cmd again."
    "completed=$(Get-Date -Format o)" | Set-Content -LiteralPath (Join-Path $OutDir "DONE.txt") -Encoding ASCII
}
catch {
    "error=$($_.Exception.Message)" | Set-Content -LiteralPath (Join-Path $OutDir "ERROR.txt") -Encoding ASCII
}

