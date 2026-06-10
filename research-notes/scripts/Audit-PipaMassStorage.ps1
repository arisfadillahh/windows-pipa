$ErrorActionPreference = 'Stop'
$OutDir = '<ARTIFACT_DIR>'
$DiskPartInput = Join-Path $OutDir 'pipa-mass-storage-audit.diskpart'
$LogPath = Join-Path $OutDir 'pipa-mass-storage-audit.log'

@'
rescan
list disk
select disk 2
detail disk
list partition
exit
'@ | Set-Content -LiteralPath $DiskPartInput -Encoding ASCII

& diskpart.exe /s $DiskPartInput 2>&1 |
    Set-Content -LiteralPath $LogPath -Encoding Unicode

