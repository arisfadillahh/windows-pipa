$ErrorActionPreference = "SilentlyContinue"
$out = "C:\woa\crashinfo.txt"
"=== pipa crash info $(Get-Date -Format o) ===" | Set-Content -LiteralPath $out -Encoding ASCII

"== last BugCheck events (System log, id 1001) ==" | Add-Content $out
Get-WinEvent -FilterHashtable @{ LogName='System'; Id=1001 } -MaxEvents 6 -ErrorAction SilentlyContinue |
    ForEach-Object { (("[{0:yyyy-MM-dd HH:mm:ss}] {1}" -f $_.TimeCreated, $_.Message) -replace "`r`n"," ") } | Add-Content $out

"== Kernel-Power 41 (dirty restarts) ==" | Add-Content $out
Get-WinEvent -FilterHashtable @{ LogName='System'; ProviderName='Microsoft-Windows-Kernel-Power'; Id=41 } -MaxEvents 4 -ErrorAction SilentlyContinue |
    ForEach-Object { "[{0:HH:mm:ss}] id41" -f $_.TimeCreated } | Add-Content $out

"== minidumps (parsed bugcheck) ==" | Add-Content $out
Get-ChildItem 'C:\Windows\Minidump\*.dmp' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 5 | ForEach-Object {
    $b = [IO.File]::ReadAllBytes($_.FullName)
    $code='?'; $p1='?'
    if ($b.Length -gt 0x60 -and [Text.Encoding]::ASCII.GetString($b,0,8) -eq 'PAGEDU64') {
        $code = '0x{0:X8}' -f [BitConverter]::ToUInt32($b,0x38)
        $p1   = '0x{0:X}'  -f [BitConverter]::ToUInt64($b,0x40)
    }
    "$($_.Name)  $([math]::Round($_.Length/1kb))KB  bugcheck=$code  p1=$p1  $($_.LastWriteTime)" | Add-Content $out
}

"== pipakbd diag (how far SelfManagedIoInit got before crash) ==" | Add-Content $out
$d = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\pipakbd' -ErrorAction SilentlyContinue
if ($d) {
    "EnableOk=$($d.EnableOk)  EnableStatus=0x$('{0:X8}' -f [int]$d.EnableStatus)  ReadStatus=0x$('{0:X8}' -f [int]$d.ReadStatus)  ReadBytes=$($d.ReadBytes)  ReadHead=0x$('{0:X8}' -f [int]$d.ReadHead)" | Add-Content $out
} else { "(no pipakbd diag values written - crash happened before/at first I2C op)" | Add-Content $out }

Start-Process notepad.exe $out
