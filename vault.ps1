<#
Drop this file (and vault.cmd, optionally) into any folder with C source code
and run it. It fetches/updates the code-graph-vault tool into a local cache,
installs its dependencies once, auto-detects inc/src module folders under
the current directory, and generates an Obsidian vault next to this script.

Usage:
  .\vault.ps1                          # auto-detect everything
  .\vault.ps1 -OutDir .\my-vault        # custom output folder
  .\vault.ps1 -Roots .\device,.\user    # explicit source roots
#>

param(
    [string]$OutDir = (Join-Path $PSScriptRoot "graph-vault"),
    [string[]]$Roots
)

$ErrorActionPreference = "Stop"

$ToolHome = Join-Path $env:LOCALAPPDATA "code-graph-vault"
$RepoUrl = "https://github.com/SolarljodDev/code-graph-vault.git"

function Search-CommonDirs($exeName) {
    $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, "$env:LOCALAPPDATA\Programs") |
        Where-Object { $_ -and (Test-Path $_) }
    foreach ($root in $roots) {
        $found = Get-ChildItem -Path $root -Filter $exeName -Recurse -Depth 3 -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    return $null
}

function Find-Tool($name, $exeName, $extraCandidates, $hint) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    foreach ($candidate in $extraCandidates) {
        if ($candidate -and (Test-Path $candidate)) { return $candidate }
    }

    $found = Search-CommonDirs $exeName
    if ($found) { return $found }

    throw "'$name' not found anywhere on this machine. $hint"
}

function Use-ToolDir($exePath) {
    $dir = Split-Path $exePath -Parent
    if ($env:PATH -notlike "*$dir*") {
        $env:PATH = "$dir;$env:PATH"
    }
}

function Ensure-Tool {
    $gitPath = Find-Tool "git" "git.exe" @(
        "$env:ProgramFiles\Git\cmd\git.exe",
        "${env:ProgramFiles(x86)}\Git\cmd\git.exe",
        "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe"
    ) "Install Git: https://git-scm.com/downloads"
    Use-ToolDir $gitPath

    $nodePath = Find-Tool "node" "node.exe" @(
        "$env:ProgramFiles\nodejs\node.exe",
        "${env:ProgramFiles(x86)}\nodejs\node.exe",
        "$env:LOCALAPPDATA\Programs\nodejs\node.exe",
        "$env:APPDATA\npm\node.exe",
        "$(if ($env:NVM_SYMLINK) { Join-Path $env:NVM_SYMLINK 'node.exe' })"
    ) "Install Node.js: https://nodejs.org"
    Use-ToolDir $nodePath

    if (-not (Test-Path $ToolHome)) {
        Write-Host "Cloning code-graph-vault into $ToolHome ..."
        git clone --depth 1 $RepoUrl $ToolHome | Out-Null
    } else {
        Write-Host "Updating code-graph-vault ..."
        git -C $ToolHome pull --ff-only 2>$null | Out-Null
    }

    if (-not (Test-Path (Join-Path $ToolHome "node_modules"))) {
        Write-Host "Installing tool dependencies (one-time) ..."
        Push-Location $ToolHome
        try { npm install --no-fund --no-audit } finally { Pop-Location }
    }
}

function Find-SourceRoots {
    $found = @(
        Get-ChildItem -Path $PSScriptRoot -Recurse -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -in @("inc", "src") -and $_.FullName -ne $OutDir } |
            ForEach-Object { $_.Parent.FullName } |
            Select-Object -Unique
    )
    if ($found.Count -eq 0) {
        return @($PSScriptRoot)
    }
    return $found
}

Ensure-Tool

if (-not $Roots -or $Roots.Count -eq 0) {
    $Roots = Find-SourceRoots
}

Write-Host "Source roots: $($Roots -join ', ')"
Write-Host "Output dir:   $OutDir"
Write-Host ""

node (Join-Path $ToolHome "index.mjs") $OutDir @Roots

Write-Host ""
Write-Host "Done. Open '$OutDir' as a vault in Obsidian (File -> Open folder as vault)."
