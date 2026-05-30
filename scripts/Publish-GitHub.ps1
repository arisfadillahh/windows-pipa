[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $RepositoryUrl,
    [string] $Branch = 'main',
    [switch] $ForceRemote
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git is not installed or not on PATH."
}

$inside = git rev-parse --is-inside-work-tree 2>$null
if ($inside -ne 'true') {
    throw "Run this script from inside the pipa-woa repository."
}

$status = git status --short
if ($status) {
    throw "Working tree is not clean. Commit or discard changes before publishing."
}

git branch -M $Branch

$existingRemote = git remote get-url origin 2>$null
if ($existingRemote) {
    if (-not $ForceRemote) {
        throw "Remote 'origin' already exists: $existingRemote. Re-run with -ForceRemote to replace it."
    }
    git remote set-url origin $RepositoryUrl
} else {
    git remote add origin $RepositoryUrl
}

git push -u origin $Branch

