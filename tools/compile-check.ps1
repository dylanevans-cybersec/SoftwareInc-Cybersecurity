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

# ---- 1b. the game's try/catch injector ----
# Before compiling a mod the game rewrites its source with a plain text scanner (ModController.InjectTryBlocks), not a parser:
# inside a class, at brace depth 0, every '(' makes it assume the next '{' is a method body and wrap it in "try { ... }".
# That is right for methods and constructors, but a field initializer with a call (= new List<T>(), = Foo()) makes it
# grab the next block, and if that block is a property or the end of the class the compiled result is invalid
# (CS1519 "Unexpected symbol 'try' in class, struct or interface member declaration"). This repeats the scan and reports
# any '(' at class level whose next '{' is not directly preceded by ')'. It also flags character literals the scanner cannot read.
function Mask-Source([string]$text, [bool]$keepChars = $false) {
    # comments and string literals become spaces (line numbers stay right); character literals too unless $keepChars
    $pattern = '//.*?$|/\*.*?\*/|@"(?:[^"]|"")*"|"(?:\\.|[^"\\])*"'
    if (-not $keepChars) { $pattern += '|''(?:\\.|[^''\\])+''' }
    [regex]::Replace($text, $pattern, { param($m) ($m.Value -replace '[^\r\n]', ' ') }, 'Multiline, Singleline')
}
function Line-Of([string]$s, [int]$index) { ($s.Substring(0, $index) -split "`n").Count }

foreach ($f in $files) {
    $text = [IO.File]::ReadAllText($f.FullName)
    $code = Mask-Source $text

    $withChars = Mask-Source $text $true      # comments and strings blanked, character literals still visible
    foreach ($m in [regex]::Matches($withChars, '''(?:\\.|[^''\\\r\n])+''')) {
        if ($m.Value -match '[{}()"]') {
            Write-Host ("INJECT {0}:{1} : character literal {2} confuses the game's try/catch injector; use a string or a constant instead" -f $f.Name, (Line-Of $withChars $m.Index), $m.Value) -ForegroundColor Red
            $problems++
        }
    }

    # the injector ends a string at the first '"' it sees, so an escaped quote inside a string throws its brace tracking off
    $noComments = [regex]::Replace($text, '//.*?$|/\*.*?\*/', { param($m) ($m.Value -replace '[^\r\n]', ' ') }, 'Multiline, Singleline')
    foreach ($m in [regex]::Matches($noComments, '\\"')) {
        Write-Host ("INJECT {0}:{1} : escaped quote inside a string confuses the game's try/catch injector; build the text another way (a char code, a constant, or single quotes)" -f $f.Name, (Line-Of $noComments $m.Index)) -ForegroundColor Red
        $problems++
    }

    $pos = 0
    while ($pos -lt $code.Length) {
        $kw = [regex]::Match($code.Substring($pos), '\b(class|struct)\b')
        if (-not $kw.Success) { break }
        $open = $code.IndexOf('{', $pos + $kw.Index)
        if ($open -lt 0) { break }
        $i = $open + 1
        $depth = 0
        while ($i -lt $code.Length -and $depth -ge 0) {
            $c = $code[$i]
            if ($c -eq '{') { $depth++ }
            elseif ($c -eq '}') { $depth-- }
            elseif ($depth -eq 0 -and $c -eq '(') {
                $rest = $code.Substring($i)
                $b = $rest.IndexOf('{')
                $e = $rest.IndexOf('=>')
                if ($b -lt 0) { break }
                if ($e -ge 0 -and $e -lt $b) { $i += [Math]::Max(0, $rest.IndexOf(';')); continue }
                $between = $rest.Substring(0, $b)
                $before = $code.Substring(0, $i + $b).TrimEnd()
                if ($between.Contains('}') -or -not $before.EndsWith(')')) {
                    Write-Host ("INJECT {0}:{1} : '(' at class level whose next '{{' is not a method body; the game's injector would wrap the wrong block in try. Move the initializer into a constructor or OnActivate, or put a method before that block" -f $f.Name, (Line-Of $code $i)) -ForegroundColor Red
                    $problems++
                }
                # skip the whole block, as the injector does
                $d = 0
                $k = $i + $b
                while ($k -lt $code.Length) {
                    if ($code[$k] -eq '{') { $d++ } elseif ($code[$k] -eq '}') { $d--; if ($d -eq 0) { break } }
                    $k++
                }
                $i = $k
            }
            $i++
        }
        $pos = [Math]::Max($i, $open + 1)
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
