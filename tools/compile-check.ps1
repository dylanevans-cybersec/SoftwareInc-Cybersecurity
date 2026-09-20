# Compiles DLLMods\Cybersecurity\*.cs with the game's own C# compiler (mcs.dll) against the game's assemblies,
# using the same language limit the game applies to Workshop-safe mods (C# 3), and scans for the things the game forbids.
# Nothing is installed or written into the game; the DLL goes to a temp folder and is thrown away.
# Usage: powershell -File tools\compile-check.ps1 [-GameDir "D:\...\Software Inc"]
param(
    [string]$GameDir = "D:\SteamLibrary\steamapps\common\Software Inc"
)

# mcs.dll is a 32-bit assembly, so re-run this script in 32-bit PowerShell when needed.
if ([Environment]::Is64BitProcess) {
    $ps32 = "$env:WINDIR\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
    & $ps32 -NoProfile -File $PSCommandPath -GameDir $GameDir
    exit $LASTEXITCODE
}

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root "DLLMods\Cybersecurity"
$managed = Join-Path $GameDir "Software Inc_Data\Managed"
$files = @(Get-ChildItem $src -Filter *.cs -File -ErrorAction SilentlyContinue)
if ($files.Count -eq 0) { Write-Host "no .cs files in $src"; exit 1 }

$problems = 0

# ---- 1. things the game's mod security check or compiler rejects ----
$rules = @(
    @{ Pattern = '\benum\s+\w+';                          Why = 'declaring an enum crashes the game when it compiles .cs files (wiki)' },
    @{ Pattern = 'System\.IO|using\s+System\.IO';          Why = 'System.IO is prohibited for game-compiled mods' },
    @{ Pattern = 'System\.Reflection';                     Why = 'System.Reflection is prohibited for game-compiled mods' },
    @{ Pattern = 'UnityEngine\.WWW\b|new\s+WWW\s*\(';      Why = 'UnityEngine.WWW is prohibited for game-compiled mods' },
    @{ Pattern = 'GiveMeFreedom';                          Why = 'GiveMeFreedom makes the mod ineligible for the Steam Workshop' }
)
# (C# 6 syntax such as interpolation, ?. and expression-bodied members is rejected by the compiler itself via -langversion:3)
foreach ($f in $files) {
    $text = [IO.File]::ReadAllText($f.FullName)
    # strip comments and string literals so text inside them does not trigger rules
    $code = [regex]::Replace($text, '//.*?$|/\*.*?\*/|@"(?:[^"]|"")*"|"(?:\\.|[^"\\])*"', '', 'Multiline, Singleline')
    foreach ($r in $rules) {
        foreach ($m in [regex]::Matches($code, $r.Pattern)) {
            $line = ($code.Substring(0, $m.Index) -split "`n").Count
            Write-Host ("RULE   {0}:{1} : {2}" -f $f.Name, $line, $r.Why) -ForegroundColor Red
            $problems++
        }
    }
}

# ---- 2. real compile with the game's compiler ----
$out = Join-Path $env:TEMP "cybersecurity-compile-check.dll"
if (Test-Path $out) { Remove-Item $out -Force }

# Standard libraries come from the running framework (the game's own mscorlib fails .NET's strong-name check when loaded here).
$refNames = @("Assembly-CSharp", "Assembly-CSharp-firstpass", "UnityEngine", "UnityEngine.CoreModule", "UnityEngine.UI", "UnityEngine.UIModule",
              "UnityEngine.TextRenderingModule", "UnityEngine.IMGUIModule", "UnityEngine.PhysicsModule", "UnityEngine.AnimationModule", "Unity.TextMeshPro")
$args = @("-target:library", "-out:$out", "-langversion:3", "-nowarn:0169,0414,0649")
foreach ($n in $refNames) {
    $p = Join-Path $managed "$n.dll"
    if (Test-Path $p) { $args += "-r:$p" }
}
foreach ($f in $files) { $args += $f.FullName }

$asm = [Reflection.Assembly]::LoadFrom((Join-Path $managed "mcs.dll"))
$entry = $asm.GetType("Mono.CSharp.CompilerCallableEntryPoint")
$sw = New-Object System.IO.StringWriter
$ok = $entry::InvokeCompiler([string[]]$args, $sw)
$output = $sw.ToString().Trim()
if ($output) { Write-Host $output }

if ($ok -and (Test-Path $out)) {
    Write-Host "compile: OK ($($files.Count) file(s), C# 3, game assemblies)" -ForegroundColor Green
} else {
    Write-Host "compile: FAILED" -ForegroundColor Red
    $problems++
}
if ($problems -gt 0) { exit 1 }
