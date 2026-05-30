$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
    $root = Split-Path -Parent $PSScriptRoot
    return (Resolve-Path $root).Path
}

function Write-Step {
    param([Parameter(Mandatory)] [string] $Message)
    Write-Host "[*] $Message" -ForegroundColor Cyan
}

function Write-Warn {
    param([Parameter(Mandatory)] [string] $Message)
    Write-Host "[!] $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([Parameter(Mandatory)] [string] $Message)
    Write-Host "[x] $Message" -ForegroundColor Red
}

function Assert-Windows {
    if (-not $IsWindows -and $PSVersionTable.PSEdition -eq 'Core') {
        throw "This script must run on Windows."
    }
}

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $adminRole = [Security.Principal.WindowsBuiltInRole]::Administrator
    if (-not $principal.IsInRole($adminRole)) {
        throw "Run PowerShell as Administrator."
    }
}

function ConvertTo-DriveRoot {
    param([Parameter(Mandatory)] [string] $Drive)

    if ($Drive -match '^[A-Za-z]$') {
        return "$($Drive.ToUpper()):\"
    }

    if ($Drive -match '^[A-Za-z]:\\?$') {
        return "$($Drive.Substring(0, 1).ToUpper()):\"
    }

    throw "Invalid drive '$Drive'. Use a drive letter such as W or S."
}

function Get-DriveLetterOnly {
    param([Parameter(Mandatory)] [string] $Drive)
    $root = ConvertTo-DriveRoot -Drive $Drive
    return $root.Substring(0, 1)
}

function Resolve-LocalTool {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [string] $ExplicitPath
    )

    if ($ExplicitPath) {
        if (-not (Test-Path -LiteralPath $ExplicitPath)) {
            throw "Tool '$Name' not found at '$ExplicitPath'."
        }
        return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }

    $repoRoot = Get-RepoRoot
    $local = Join-Path $repoRoot "tools\platform-tools\$Name.exe"
    if (Test-Path -LiteralPath $local) {
        return (Resolve-Path -LiteralPath $local).Path
    }

    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    throw "Tool '$Name' not found. Run scripts\Fetch-Dependencies.ps1 first."
}

function Invoke-Native {
    param(
        [Parameter(Mandatory)] [string] $FilePath,
        [Parameter(Mandatory)] [string[]] $Arguments,
        [string] $LogPath,
        [switch] $AllowFailure,
        [switch] $DryRun
    )

    $display = "$FilePath $($Arguments -join ' ')"
    if ($DryRun) {
        Write-Host "[dry-run] $display"
        return @()
    }

    Write-Host "> $display"
    $output = & $FilePath @Arguments 2>&1
    $exitCode = $LASTEXITCODE

    if ($LogPath) {
        $dir = Split-Path -Parent $LogPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
        $output | Out-File -FilePath $LogPath -Encoding utf8 -Append
    }

    $output | ForEach-Object { Write-Host $_ }

    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "Command failed with exit code ${exitCode}: $display"
    }

    return $output
}

function Confirm-Destructive {
    param(
        [Parameter(Mandatory)] [bool] $AllowDestructive,
        [Parameter(Mandatory)] [string] $Message
    )

    if (-not $AllowDestructive) {
        throw "$Message`nRe-run with -AllowDestructive after verifying the target."
    }
}

function New-CaptureDirectory {
    param([string] $Prefix = 'capture')
    $repoRoot = Get-RepoRoot
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dir = Join-Path $repoRoot "captures\$Prefix-$timestamp"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    return $dir
}

function Get-WindowsImageFile {
    param([Parameter(Mandatory)] [string] $IsoRoot)

    $wim = Join-Path $IsoRoot 'sources\install.wim'
    $esd = Join-Path $IsoRoot 'sources\install.esd'

    if (Test-Path -LiteralPath $wim) {
        return $wim
    }

    if (Test-Path -LiteralPath $esd) {
        return $esd
    }

    throw "No install.wim or install.esd found under $IsoRoot\sources."
}

Export-ModuleMember -Function *
