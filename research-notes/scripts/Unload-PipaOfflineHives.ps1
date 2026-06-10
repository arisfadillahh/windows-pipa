$ErrorActionPreference = 'Continue'
$Log = '<WORKSPACE>\offline-boot-repair-20260604\unload-hives.log'

"START $(Get-Date -Format o)" | Set-Content -LiteralPath $Log
foreach ($hive in @('HKLM\PipaSYSTEM', 'HKLM\PipaSOFTWARE')) {
    & reg.exe unload $hive 2>&1 | Add-Content -LiteralPath $Log
    "EXIT $hive $LASTEXITCODE" | Add-Content -LiteralPath $Log
}
"END $(Get-Date -Format o)" | Add-Content -LiteralPath $Log

