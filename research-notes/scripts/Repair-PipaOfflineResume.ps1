param(
    [Parameter(Mandatory = $true)]
    [string] $WorkDir
)

$ErrorActionPreference = 'Stop'
$LogPath = Join-Path $WorkDir 'offline-resume-repair.log'

function Log {
    param([string] $Message)
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $line | Tee-Object -FilePath $LogPath -Append
}

function Run {
    param(
        [string] $File,
        [string[]] $Arguments,
        [switch] $AllowFailure
    )
    Log ("RUN {0} {1}" -f $File, ($Arguments -join ' '))
    $output = & $File @Arguments 2>&1
    $exit = $LASTEXITCODE
    $output | Tee-Object -FilePath $LogPath -Append | Write-Host
    Log "EXIT $exit"
    if (-not $AllowFailure -and $exit -ne 0) {
        throw "$File failed with exit $exit"
    }
}

if (-not ([Security.Principal.WindowsPrincipal]::new(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Administrator token required.'
}

$bcd = Join-Path $WorkDir 'BCD'
$system = Join-Path $WorkDir 'SYSTEM'
$software = Join-Path $WorkDir 'SOFTWARE'
foreach ($path in @($bcd, $system, $software)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing offline file: $path"
    }
    Copy-Item -LiteralPath $path -Destination "$path.pre-resume-fix" -Force
}

Remove-Item -LiteralPath $LogPath -Force -ErrorAction SilentlyContinue
Log '=== Offline resume repair start ==='
Log "WorkDir=$WorkDir"

Run bcdedit.exe @('/store', $bcd, '/enum', 'all')
Run bcdedit.exe @('/store', $bcd, '/deletevalue', '{default}', 'resumeobject') -AllowFailure
Run bcdedit.exe @('/store', $bcd, '/set', '{default}', 'bootlog', 'Yes')
Run bcdedit.exe @('/store', $bcd, '/set', '{default}', 'sos', 'Yes')
Run bcdedit.exe @('/store', $bcd, '/set', '{default}', 'recoveryenabled', 'Yes')
Run bcdedit.exe @('/store', $bcd, '/set', '{default}', 'bootstatuspolicy', 'IgnoreAllFailures')
Run bcdedit.exe @('/store', $bcd, '/set', '{bootmgr}', 'displaybootmenu', 'Yes')
Run bcdedit.exe @('/store', $bcd, '/timeout', '5')
Run bcdedit.exe @('/store', $bcd, '/enum', 'all')

Run reg.exe @('load', 'HKLM\PipaSYSTEM', $system)
try {
    $sets = Get-ChildItem -LiteralPath 'Registry::HKEY_LOCAL_MACHINE\PipaSYSTEM' |
        Where-Object { $_.PSChildName -match '^ControlSet\d{3}$' }
    foreach ($set in $sets) {
        $sessionPower = "HKLM\PipaSYSTEM\$($set.PSChildName)\Control\Session Manager\Power"
        $controlPower = "HKLM\PipaSYSTEM\$($set.PSChildName)\Control\Power"
        Run reg.exe @('add', $sessionPower, '/v', 'HiberbootEnabled', '/t', 'REG_DWORD', '/d', '0', '/f')
        Run reg.exe @('add', $controlPower, '/v', 'HibernateEnabled', '/t', 'REG_DWORD', '/d', '0', '/f')
        Run reg.exe @('add', $controlPower, '/v', 'HibernateEnabledDefault', '/t', 'REG_DWORD', '/d', '0', '/f')
    }
} finally {
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    Run reg.exe @('unload', 'HKLM\PipaSYSTEM')
}

Run reg.exe @('load', 'HKLM\PipaSOFTWARE', $software)
try {
    Run reg.exe @(
        'add',
        'HKLM\PipaSOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings',
        '/v', 'ShowHibernateOption',
        '/t', 'REG_DWORD',
        '/d', '0',
        '/f'
    )
} finally {
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    Run reg.exe @('unload', 'HKLM\PipaSOFTWARE')
}

Get-FileHash -Algorithm SHA256 -LiteralPath $bcd, $system, $software |
    Format-Table -AutoSize |
    Out-String |
    Tee-Object -FilePath $LogPath -Append |
    Write-Host

Log '=== Offline resume repair end ==='

