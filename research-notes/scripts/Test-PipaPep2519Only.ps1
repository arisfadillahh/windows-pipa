$ErrorActionPreference = 'Continue'

$Root = 'C:\woa\oneshot\pep2519'
$DriverInf = 'C:\woa\oneshot\drivers\qcpep\qcpep.wp8250.inf'
$Result = Join-Path $Root 'RESULT.txt'
$Transcript = Join-Path $Root ('transcript-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')

New-Item -ItemType Directory -Force -Path $Root | Out-Null
Start-Transcript -LiteralPath $Transcript -Force | Out-Null

function Write-Result($Message) {
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "[$stamp] $Message" | Tee-Object -FilePath $Result -Append
}

function Run($File, [string[]]$Arguments) {
    Write-Result "RUN $File $($Arguments -join ' ')"
    $p = Start-Process -FilePath $File -ArgumentList $Arguments -Wait -PassThru -NoNewWindow -RedirectStandardOutput (Join-Path $Root 'last-stdout.txt') -RedirectStandardError (Join-Path $Root 'last-stderr.txt')
    Get-Content -LiteralPath (Join-Path $Root 'last-stdout.txt') -ErrorAction SilentlyContinue | Tee-Object -FilePath $Result -Append
    Get-Content -LiteralPath (Join-Path $Root 'last-stderr.txt') -ErrorAction SilentlyContinue | Tee-Object -FilePath $Result -Append
    Write-Result "EXIT $($p.ExitCode)"
    return $p.ExitCode
}

Write-Result '=== PIPA PEP2519-ONLY TEST START ==='
Write-Result "Running as $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Result "DriverInf=$DriverInf"

foreach ($svc in @('qcppx','qcPILC','qcpil','qcpil8250','qcpmic','qcpmicapps','qcpmiceic','qcpmicext','qcpmicglink','qcpmgpio','qcpmictcc','qcsmmu','qciommu','qcspmi','qcscm','qcspi')) {
    & reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\$svc" /v Start /t REG_DWORD /d 4 /f | Out-Null
}

Run 'bcdedit.exe' @('/set', 'testsigning', 'on') | Out-Null

Write-Result '--- BEFORE PNP ---'
Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match 'QCOM2519|QCOM1A17|PNP0D80|QCOM050F|QCOM0593' } |
    Format-Table -AutoSize | Out-String | Tee-Object -FilePath $Result -Append
& sc.exe query qcpep | Tee-Object -FilePath $Result -Append

if (-not (Test-Path -LiteralPath $DriverInf)) {
    Write-Result "MISSING DRIVER INF: $DriverInf"
    Write-Result '=== PIPA PEP2519-ONLY TEST END: MISSING INF ==='
    Stop-Transcript | Out-Null
    exit 20
}

Write-Result '--- INSTALL QCPep only ---'
$exit = Run 'pnputil.exe' @('/add-driver', $DriverInf, '/install')
Start-Sleep -Seconds 25

Write-Result '--- AFTER PNP ---'
Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match 'QCOM2519|QCOM1A17|PNP0D80|QCOM050F|QCOM0593' } |
    Format-Table -AutoSize | Out-String | Tee-Object -FilePath $Result -Append
Get-PnpDevice | Where-Object { $_.InstanceId -match 'QCOM2519|QCOM1A17|PNP0D80|QCOM050F|QCOM0593' } |
    Format-List * | Out-String | Tee-Object -FilePath (Join-Path $Root 'pnp-detail.txt') -Append
& pnputil.exe /enum-drivers | Select-String -Pattern 'qcpep|Published Name|Original Name|Provider Name|Class Name|Driver Version|Signer Name' -Context 0,4 |
    Out-String | Tee-Object -FilePath (Join-Path $Root 'pnputil-drivers-qcpep.txt') -Append
& sc.exe query qcpep | Tee-Object -FilePath $Result -Append
& reg.exe query HKLM\SYSTEM\CurrentControlSet\Services\qcpep /s | Tee-Object -FilePath (Join-Path $Root 'service-qcpep.reg.txt') -Append

Write-Result "pnputil_exit=$exit"
Write-Result '=== PIPA PEP2519-ONLY TEST END ==='
Stop-Transcript | Out-Null

