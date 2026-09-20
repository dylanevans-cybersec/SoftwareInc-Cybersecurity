# Removes the junctions created by link.ps1 (and the old separate-folder ones from earlier layouts).
# Only the links are removed; project files are untouched.
param(
    [string]$GameDir = "D:\SteamLibrary\steamapps\common\Software Inc"
)

$ErrorActionPreference = "Stop"

foreach ($rel in "DLLMods\Cybersecurity", "Mods\Cybersecurity", "Furniture\Cybersecurity") {
    $dst = Join-Path $GameDir $rel
    if (-not (Test-Path $dst)) { continue }
    $item = Get-Item $dst -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        # Delete the link itself, never recurse into the target.
        [IO.Directory]::Delete($dst, $false)
        Write-Host "unlinked: $dst"
    } else {
        Write-Host "skipped (not a link): $dst"
    }
}
