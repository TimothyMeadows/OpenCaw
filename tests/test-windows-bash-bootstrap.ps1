[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw "FAIL: $Message"
    }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$installer = Join-Path $repoRoot 'commands\install-windows-bash.ps1'
$installerText = Get-Content -Raw -LiteralPath $installer
$null = [scriptblock]::Create($installerText)

if ($env:OS -ne 'Windows_NT') {
    $output = @(& $installer)
    Assert-True ($output -contains 'WINDOWS_BASH_STATUS=NOT_REQUIRED') 'non-Windows execution was not a clean no-op'
    Write-Output 'Windows Bash PowerShell tests passed (non-Windows no-op).'
    exit 0
}

$tempParent = [System.IO.Path]::GetTempPath()
$tempRoot = Join-Path $tempParent ("opencaw-windows-bash-{0}" -f [guid]::NewGuid().ToString('N'))
$resolvedTempParent = [System.IO.Path]::GetFullPath($tempParent)
$resolvedTempRoot = [System.IO.Path]::GetFullPath($tempRoot)
Assert-True ($resolvedTempRoot.StartsWith($resolvedTempParent, [System.StringComparison]::OrdinalIgnoreCase)) 'temporary test root escaped the system temp directory'

New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
    $fakeBash = Join-Path $tempRoot 'bash.exe'
    Set-Content -LiteralPath $fakeBash -Value 'fixture' -NoNewline

    $discoveryOutput = @(& $installer -Provider GitBash -GitBashPath $fakeBash)
    Assert-True ($discoveryOutput -contains 'WINDOWS_BASH_STATUS=FOUND') 'explicit Git Bash discovery failed'
    Assert-True ($discoveryOutput -contains 'WINDOWS_BASH_PROVIDER=GitBash') 'Git Bash provider was not selected'
    Assert-True ($discoveryOutput -contains "WINDOWS_BASH_COMMAND=$fakeBash") 'resolved Git Bash path was not reported'
    Assert-True ($discoveryOutput -contains 'OPENCAW_SCAFFOLD_RUN=false') 'discovery unexpectedly ran the scaffold'

    $plannedOutput = @(& $installer -Provider GitBash -GitBashPath $fakeBash -RunScaffold -ProjectRoot $repoRoot -WhatIf)
    Assert-True ($plannedOutput -contains 'OPENCAW_SCAFFOLD_RUN=planned') 'WhatIf did not report a planned scaffold run'

    $invalidRootFailed = $false
    try {
        & $installer -Provider GitBash -GitBashPath $fakeBash -RunScaffold -ProjectRoot (Join-Path $tempRoot 'missing') 2>$null | Out-Null
    }
    catch {
        $invalidRootFailed = $true
    }
    Assert-True $invalidRootFailed 'missing project root was accepted'

    Assert-True ($installerText -match "'Git.Git'") 'Git Bash winget package id is missing'
    Assert-True ($installerText -match 'ShouldProcess') 'installation and scaffold actions are not guarded by ShouldProcess'
    Assert-True ($installerText -match '--install') 'WSL installation path is missing'
}
finally {
    if (Test-Path -LiteralPath $resolvedTempRoot) {
        Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force
    }
}

Write-Output 'Windows Bash PowerShell tests passed.'
