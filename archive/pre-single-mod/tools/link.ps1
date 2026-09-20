# Links this project's mod folders into the Software Inc. install with directory junctions,
# so the game reads the project folder directly. No admin rights needed.
# Usage: powershell -File tools\link.ps1 [-GameDir "D:\...\Software Inc"]
param(
    [string]$GameDir = "D:\SteamLibrary\steamapps\common\Software Inc"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

if (Get-Process -Name "Software Inc" -ErrorAction SilentlyContinue) {
    throw "Software Inc. is running. Close it before linking."
}
if (-not (Test-Path (Join-Path $GameDir "Software Inc.exe"))) {
    throw "Software Inc.exe not found in $GameDir"
}

# project folder -> game folder
$links = @(
    @{ Source = "Mods\Cybersecurity";    Target = "Mods\Cybersecurity" },
    @{ Source = "DLLMods\Cybersecurity"; Target = "DLLMods\Cybersecurity" }
)

foreach ($l in $links) {
    $src = Join-Path $root $l.Source
    $dst = Join-Path $GameDir $l.Target
    if (-not (Test-Path $src)) { throw "Missing project folder: $src" }

    # An empty mod folder can confuse the game's loaders, so only link folders that have content.
    if (-not (Get-ChildItem $src -Recurse -File | Select-Object -First 1)) {
        Write-Host "skipped (empty): $($l.Source)"
        continue
    }

    New-Item -ItemType Directory -Force (Split-Path -Parent $dst) | Out-Null

    if (Test-Path $dst) {
        $item = Get-Item $dst -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            Write-Host "already linked: $($l.Target)"
            continue
        }
        if (Get-ChildItem $dst -Force -Recurse -File | Select-Object -First 1) {
            throw "$dst is a real, non-empty folder. Move its contents into the project first."
        }
        Remove-Item $dst -Recurse -Force   # empty shell only
    }

    New-Item -ItemType Junction -Path $dst -Target $src | Out-Null
    Write-Host "linked: $dst -> $src"
}
