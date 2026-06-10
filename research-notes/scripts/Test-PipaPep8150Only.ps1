$ErrorActionPreference = 'Continue'

$Root = 'C:\woa\oneshot\pep8150'
$DriverInf = 'C:\woa\oneshot\drivers\qcpep8150\qcpep.wp8150.inf'
$Result = Join-Path $Root 'RESULT.txt'
$Transcript = Join-Path $Root ('transcript-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

New-Item -ItemType Directory -Force -Path $Root | Out-Null

if (-not (Test-IsAdmin)) {
    Set-Content -LiteralPath (Join-Path $Root 'UAC-REQUESTED.txt') -Value (Get-Date -Format o) -Encoding ASCII
    $arg = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath
    Start-Process -FilePath 'powershell.exe' -ArgumentList $arg -Verb RunAs
    exit 0
}

Start-Transcript -LiteralPath $Transcript -Force | Out-Null

function Write-Result($Message) {
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "[$stamp] $Message" | Tee-Object -FilePath $Result -Append
}

function Run($File, [string[]]$Arguments) {
    $stdout = Join-Path $Root 'last-stdout.txt'
    $stderr = Join-Path $Root 'last-stderr.txt'
    Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
    Write-Result "RUN $File $($Arguments -join ' ')"
    $p = Start-Process -FilePath $File -ArgumentList $Arguments -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    Get-Content -LiteralPath $stdout -ErrorAction SilentlyContinue | Tee-Object -FilePath $Result -Append
    Get-Content -LiteralPath $stderr -ErrorAction SilentlyContinue | Tee-Object -FilePath $Result -Append
    Write-Result "EXIT $($p.ExitCode)"
    return $p.ExitCode
}

function Dump-Devices($Label) {
    Write-Result "--- $Label PNP SUMMARY ---"
    Get-PnpDevice | Where-Object { $_.InstanceId -match 'QCOM0519|QCOM2519|PNP0D80|QCOM050F|QCOM0593|QCOM1A17' } |
        Sort-Object InstanceId |
        Format-Table -AutoSize | Out-String | Tee-Object -FilePath $Result -Append

    Get-PnpDevice | Where-Object { $_.InstanceId -match 'QCOM0519|QCOM2519|PNP0D80|QCOM050F|QCOM0593|QCOM1A17' } |
        Sort-Object InstanceId |
        Format-List * | Out-String | Tee-Object -FilePath (Join-Path $Root "$Label-pnp-detail.txt") -Append

    foreach ($id in @('ACPI\QCOM0519*','ACPI\QCOM2519*','ACPI\QCOM050F*','ACPI\QCOM0593*')) {
        & pnputil.exe /enum-devices /instanceid $id /drivers 2>&1 |
            Tee-Object -FilePath (Join-Path $Root "$Label-pnputil-devices.txt") -Append
    }
}

function Get-DriverPackages {
    $rows = New-Object System.Collections.Generic.List[object]
    $cur = @{}
    foreach ($line in (& pnputil.exe /enum-drivers)) {
        if ($line -match '^\s*Published Name\s*:\s*(\S+)\s*$') {
            if ($cur.ContainsKey('PublishedName')) { $rows.Add([pscustomobject]$cur) }
            $cur = @{ PublishedName = $Matches[1] }
        } elseif ($line -match '^\s*Original Name\s*:\s*(.+?)\s*$') {
            $cur.OriginalName = $Matches[1]
        } elseif ($line -match '^\s*Provider Name\s*:\s*(.+?)\s*$') {
            $cur.ProviderName = $Matches[1]
        } elseif ($line -match '^\s*Class Name\s*:\s*(.+?)\s*$') {
            $cur.ClassName = $Matches[1]
        } elseif ($line -match '^\s*Driver Version\s*:\s*(.+?)\s*$') {
            $cur.DriverVersion = $Matches[1]
        }
    }
    if ($cur.ContainsKey('PublishedName')) { $rows.Add([pscustomobject]$cur) }
    return $rows
}

Write-Result '=== PIPA PEP8150-ONLY TEST START ==='
Write-Result "Running elevated as $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Result "DriverInf=$DriverInf"

foreach ($svc in @('qcppx','qcPILC','qcpil','qcpil8250','qcpmic','qcpmicapps','qcpmiceic','qcpmicext','qcpmicglink','qcpmgpio','qcpmictcc','qcsmmu','qciommu','qcspmi','qcscm','qcspi')) {
    & reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\$svc" /v Start /t REG_DWORD /d 4 /f | Out-Null
}

Run 'bcdedit.exe' @('/set', 'testsigning', 'on') | Out-Null
Dump-Devices 'before'

Write-Result '--- EXISTING QCPep DRIVER PACKAGES ---'
$pepPackages = Get-DriverPackages | Where-Object { $_.OriginalName -match '^qcpep.*\.inf$' }
$pepPackages | Format-Table -AutoSize | Out-String | Tee-Object -FilePath $Result -Append

foreach ($pkg in $pepPackages) {
    Write-Result "Deleting existing qcpep package $($pkg.PublishedName) original=$($pkg.OriginalName)"
    Run 'pnputil.exe' @('/delete-driver', $pkg.PublishedName, '/uninstall', '/force') | Out-Null
}

if (-not (Test-Path -LiteralPath $DriverInf)) {
    Write-Result "MISSING DRIVER INF: $DriverInf"
    Write-Result '=== PIPA PEP8150-ONLY TEST END: MISSING INF ==='
    Stop-Transcript | Out-Null
    exit 20
}

Write-Result '--- INSTALL qcpep.wp8150 only ---'
$exit = Run 'pnputil.exe' @('/add-driver', $DriverInf, '/install')
Start-Sleep -Seconds 25

Dump-Devices 'after'
& pnputil.exe /enum-drivers |
    Select-String -Pattern 'qcpep|Published Name|Original Name|Provider Name|Class Name|Driver Version|Signer Name' -Context 0,4 |
    Out-String | Tee-Object -FilePath (Join-Path $Root 'pnputil-drivers-qcpep.txt') -Append
& sc.exe query qcpep | Tee-Object -FilePath $Result -Append
& reg.exe query HKLM\SYSTEM\CurrentControlSet\Services\qcpep /s | Tee-Object -FilePath (Join-Path $Root 'service-qcpep.reg.txt') -Append

Write-Result "pnputil_exit=$exit"
Write-Result '=== PIPA PEP8150-ONLY TEST END ==='
Stop-Transcript | Out-Null

