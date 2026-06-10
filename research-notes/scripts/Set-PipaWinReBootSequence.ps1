param(
    [string] $BcdPath = '<WORKSPACE>\offline-boot-repair-20260604\BCD-winre-test',
    [string] $SourceBcd = '<WORKSPACE>\offline-boot-repair-20260604\BCD',
    [string] $LogPath = '<WORKSPACE>\offline-boot-repair-20260604\winre-test-bcd.log'
)

$ErrorActionPreference = 'Stop'
$RecoveryId = '{a44c7eca-effc-11ee-9658-8ce335964172}'

function Run-BcdEdit {
    param([string[]] $Arguments)
    & bcdedit.exe @Arguments 2>&1 | Tee-Object -FilePath $LogPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "bcdedit failed: $($Arguments -join ' ')"
    }
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Administrator token required.'
}

Copy-Item -LiteralPath $SourceBcd -Destination $BcdPath -Force
"=== WINRE BCD TEST START $(Get-Date -Format o) ===" |
    Set-Content -LiteralPath $LogPath -Encoding UTF8

Run-BcdEdit @('/store', $BcdPath, '/set', '{bootmgr}', 'bootsequence', $RecoveryId)
Run-BcdEdit @('/store', $BcdPath, '/set', '{bootmgr}', 'displaybootmenu', 'yes')
Run-BcdEdit @('/store', $BcdPath, '/timeout', '3')
Run-BcdEdit @('/store', $BcdPath, '/enum', 'all')

"=== WINRE BCD TEST END $(Get-Date -Format o) ===" |
    Add-Content -LiteralPath $LogPath

