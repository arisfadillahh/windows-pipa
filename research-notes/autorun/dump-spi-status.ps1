$ErrorActionPreference = "Continue"
$Root = "C:\woa"
$RunDir = Join-Path $Root "spi-kona-run"
$OutDir = Join-Path $RunDir ("post-boot-dump-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
$LogFile = Join-Path $RunDir "dump-spi-status.log"

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

Ensure-Dir $OutDir
Start-Transcript -Path (Join-Path $OutDir "transcript.log") -Append | Out-Null
Log "Post-boot SPI status dump start: $OutDir"

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
cmd /c "wevtutil qe System /c:300 /f:text /rd:true > `"$OutDir\system-eventlog-tail.txt`" 2>&1"

$Needles = "QCOM050F|QCOM0593|QCOM050D|NVT36532|NTTS3652|NTP36532|nt36|qcspi|Nanosic|VID_2717|VID_258A|BasicDisplay|Problem|0xC0000490|CM_PROB"
Select-String -Path (Join-Path $OutDir "*") -Pattern $Needles -CaseSensitive:$false |
    Out-File -FilePath (Join-Path $OutDir "interesting-hits.txt") -Encoding utf8

"DONE: post-boot SPI status dump complete. Output: $OutDir" |
    Out-File -FilePath (Join-Path $RunDir "DONE.txt") -Encoding ascii
Log "Post-boot dump complete. Scheduling full shutdown."
shutdown.exe /s /f /t 45 /c "Codex SPI status dump complete. Full shutdown keeps WINPIPA clean."
Stop-Transcript | Out-Null

