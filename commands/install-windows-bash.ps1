[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('Auto', 'GitBash', 'WSL')]
    [string]$Provider = 'Auto',

    [switch]$Install,

    [switch]$RunScaffold,

    [string]$ProjectRoot,

    [string]$GitBashPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-HephaeraWindows {
    if ($env:OS -eq 'Windows_NT') {
        return $true
    }
    if ($PSVersionTable.ContainsKey('Platform')) {
        return $PSVersionTable.Platform -eq 'Win32NT'
    }
    return $false
}

function Resolve-ExistingGitBash {
    param([string]$ExplicitPath)

    $candidates = [System.Collections.Generic.List[string]]::new()
    if ($ExplicitPath) {
        $candidates.Add($ExplicitPath)
    }

    if (${env:ProgramFiles}) {
        $candidates.Add((Join-Path ${env:ProgramFiles} 'Git\bin\bash.exe'))
    }
    if (${env:ProgramFiles(x86)}) {
        $candidates.Add((Join-Path ${env:ProgramFiles(x86)} 'Git\bin\bash.exe'))
    }
    if ($env:LOCALAPPDATA) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe'))
    }

    $gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($gitCommand) {
        $gitRoot = Split-Path -Parent (Split-Path -Parent $gitCommand.Source)
        $candidates.Add((Join-Path $gitRoot 'bin\bash.exe'))
        $candidates.Add((Join-Path $gitRoot 'usr\bin\bash.exe'))
    }

    $pathBash = Get-Command bash.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pathBash -and $pathBash.Source -match '(?i)[\\/](Git|MSYS2?)[\\/]') {
        $candidates.Add($pathBash.Source)
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    return $null
}

function Resolve-ExistingWsl {
    $wslCommand = Get-Command wsl.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $wslCommand) {
        return $null
    }

    $distributionOutput = & $wslCommand.Source --list --quiet 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    $distributions = @(
        $distributionOutput |
            ForEach-Object { ([string]$_).Replace([char]0, [char]32).Trim() } |
            Where-Object { $_ }
    )
    if ($distributions.Count -eq 0) {
        return $null
    }

    return $wslCommand.Source
}

function Install-GitBash {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $winget) {
        throw 'winget.exe is unavailable. Install Git for Windows manually, then rerun this command without -Install.'
    }

    $arguments = @(
        'install',
        '--id', 'Git.Git',
        '--exact',
        '--source', 'winget',
        '--accept-source-agreements',
        '--accept-package-agreements'
    )
    if ($PSCmdlet.ShouldProcess('Git for Windows (Git Bash)', "$($winget.Source) $($arguments -join ' ')")) {
        & $winget.Source @arguments
        if ($LASTEXITCODE -ne 0) {
            throw "winget failed to install Git for Windows (exit $LASTEXITCODE)."
        }
    }
}

function Install-WslBash {
    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $wsl) {
        throw 'wsl.exe is unavailable. Enable the Windows Subsystem for Linux optional feature or choose -Provider GitBash.'
    }

    if ($PSCmdlet.ShouldProcess('Windows Subsystem for Linux', "$($wsl.Source) --install")) {
        & $wsl.Source --install
        if ($LASTEXITCODE -ne 0) {
            throw "wsl.exe --install failed (exit $LASTEXITCODE)."
        }
        Write-Output 'WINDOWS_BASH_RESTART_MAY_BE_REQUIRED=true'
    }
}

function Resolve-Provider {
    param([string]$RequestedProvider)

    if ($RequestedProvider -in @('Auto', 'GitBash')) {
        $gitBash = Resolve-ExistingGitBash -ExplicitPath $GitBashPath
        if ($gitBash) {
            return [pscustomobject]@{ Name = 'GitBash'; Command = $gitBash }
        }
    }

    if ($RequestedProvider -in @('Auto', 'WSL')) {
        $wsl = Resolve-ExistingWsl
        if ($wsl) {
            return [pscustomobject]@{ Name = 'WSL'; Command = $wsl }
        }
    }

    return $null
}

function Resolve-ProjectRoot {
    param([string]$RequestedRoot)

    $baselineRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
    $baselineName = Split-Path -Leaf $baselineRoot
    $baselineParent = Split-Path -Parent $baselineRoot
    $requested = if ($RequestedRoot) {
        if (-not (Test-Path -LiteralPath $RequestedRoot -PathType Container)) {
            throw "Project root does not exist: $RequestedRoot"
        }
        (Resolve-Path -LiteralPath $RequestedRoot).Path
    } else { $null }

    if ($baselineName -ceq '.hephaera') {
        if ($requested -and -not $requested.Equals($baselineParent, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'ProjectRoot must match the direct parent of the .hephaera installation.'
        }
        $resolved = $baselineParent
    } else {
        # Source checkouts support maintainer verification; hosts install only .hephaera.
        if ($baselineName.StartsWith('.') -or -not (Test-Path -LiteralPath (Join-Path $baselineRoot '.git'))) {
            throw 'Fresh host installations must be located directly at <project-root>/.hephaera.'
        }
        $ancestor = $baselineParent
        while ($ancestor) {
            if (Test-Path -LiteralPath (Join-Path $ancestor '.git')) {
                throw 'Nested Hephaera installations must use <project-root>/.hephaera.'
            }
            $nextAncestor = Split-Path -Parent $ancestor
            if ($nextAncestor -eq $ancestor) { break }
            $ancestor = $nextAncestor
        }
        $resolved = if ($requested) { $requested } else { $baselineRoot }
    }
    foreach ($component in @((Join-Path $resolved '.hephaera'), (Join-Path $resolved '.hephaera/.cache'))) {
        $item = Get-Item -LiteralPath $component -Force -ErrorAction SilentlyContinue
        if ($item -and ((($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or -not $item.PSIsContainer)) {
            throw 'The fixed .hephaera/.cache path requires real directories without links or file collisions.'
        }
    }
    return $resolved
}

function Invoke-HephaeraScaffold {
    param(
        [pscustomobject]$SelectedProvider,
        [string]$ResolvedProjectRoot
    )

    $scaffoldScript = Join-Path $PSScriptRoot 'create-host-ai-scaffold.sh'
    if (-not (Test-Path -LiteralPath $scaffoldScript -PathType Leaf)) {
        throw "Hephaera scaffold command not found: $scaffoldScript"
    }

    $scaffoldTarget = if ($ResolvedProjectRoot) { $ResolvedProjectRoot } else { 'auto-resolved project' }
    if (-not $PSCmdlet.ShouldProcess($scaffoldTarget, "Run scaffold with $($SelectedProvider.Name)")) {
        return
    }

    if ($SelectedProvider.Name -eq 'GitBash') {
        $previousProjectRoot = $env:HEPHAERA_PROJECT_ROOT
        try {
            if ($ResolvedProjectRoot) {
                $env:HEPHAERA_PROJECT_ROOT = $ResolvedProjectRoot
            }
            & $SelectedProvider.Command $scaffoldScript
            if ($LASTEXITCODE -ne 0) {
                throw "Hephaera scaffold failed under Git Bash (exit $LASTEXITCODE)."
            }
        }
        finally {
            $env:HEPHAERA_PROJECT_ROOT = $previousProjectRoot
        }
        return
    }

    $hephaeraRoot = Split-Path -Parent $PSScriptRoot
    $arguments = [System.Collections.Generic.List[string]]::new()
    $arguments.Add('--cd')
    $arguments.Add($hephaeraRoot)
    if ($ResolvedProjectRoot) {
        $wslProjectOutput = @(& $SelectedProvider.Command --cd $ResolvedProjectRoot pwd)
        $wslProjectRoot = ($wslProjectOutput -join "`n").Trim()
        if ($LASTEXITCODE -ne 0 -or -not $wslProjectRoot) {
            throw 'Unable to resolve the project-root path through WSL.'
        }
        $arguments.Add('env')
        $arguments.Add("HEPHAERA_PROJECT_ROOT=$wslProjectRoot")
    }
    $arguments.Add('bash')
    $arguments.Add('./commands/create-host-ai-scaffold.sh')

    & $SelectedProvider.Command @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Hephaera scaffold failed under WSL (exit $LASTEXITCODE)."
    }
}

if (-not (Test-HephaeraWindows)) {
    Write-Output 'WINDOWS_BASH_STATUS=NOT_REQUIRED'
    Write-Output 'WINDOWS_BASH_REASON=Linux and macOS use their existing Bash runtime.'
    exit 0
}

$resolvedRoot = if ($RunScaffold) { Resolve-ProjectRoot -RequestedRoot $ProjectRoot } else { $null }

$selected = Resolve-Provider -RequestedProvider $Provider
if (-not $selected -and $Install) {
    $installProvider = if ($Provider -eq 'Auto') { 'GitBash' } else { $Provider }
    if ($installProvider -eq 'GitBash') {
        Install-GitBash
    }
    else {
        Install-WslBash
    }

    if ($WhatIfPreference) {
        Write-Output 'WINDOWS_BASH_STATUS=INSTALL_PLANNED'
        Write-Output "WINDOWS_BASH_PROVIDER=$installProvider"
        exit 0
    }

    $selected = Resolve-Provider -RequestedProvider $installProvider
}

if (-not $selected) {
    $recommendedProvider = if ($Provider -eq 'Auto') { 'GitBash' } else { $Provider }
    Write-Output 'WINDOWS_BASH_STATUS=MISSING'
    Write-Output "WINDOWS_BASH_RECOMMENDED_PROVIDER=$recommendedProvider"
    Write-Output "WINDOWS_BASH_INSTALL_COMMAND=powershell -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Provider $recommendedProvider -Install"
    Write-Error 'No usable Bash provider was found. No software was installed; rerun with -Install or install the provider manually.' -ErrorAction Continue
    exit 2
}

Write-Output 'WINDOWS_BASH_STATUS=FOUND'
Write-Output "WINDOWS_BASH_PROVIDER=$($selected.Name)"
Write-Output "WINDOWS_BASH_COMMAND=$($selected.Command)"
Write-Output 'WINDOWS_BASH_INSTALL_REQUIRED=false'

if ($RunScaffold) {
    Invoke-HephaeraScaffold -SelectedProvider $selected -ResolvedProjectRoot $resolvedRoot
    if ($WhatIfPreference) {
        Write-Output 'HEPHAERA_SCAFFOLD_RUN=planned'
    }
    else {
        Write-Output 'HEPHAERA_SCAFFOLD_RUN=true'
    }
}
else {
    Write-Output 'HEPHAERA_SCAFFOLD_RUN=false'
}
