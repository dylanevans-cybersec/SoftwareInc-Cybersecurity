# Dumps members of classes in the game's Assembly-CSharp.dll (read-only, uses the Mono.Cecil that ships with the game).
# Software Inc.'s code-mod API is barely documented, so use this instead of guessing.
#
#   tools\dump-api.ps1 -Type Company                       all members
#   tools\dump-api.ps1 -Type Company -Match 'Money|Fans'   only members whose name matches
#   tools\dump-api.ps1 -Type 'Employee/EmployeeRole' -Enum list enum values (nested types use "/")
#   tools\dump-api.ps1 -Find 'Lawsuit|Incident'            list type names that match
param(
    [string]$Type,
    [string]$Match = '.',
    [string]$Find,
    [switch]$Enum,
    [string]$GameDir = "D:\SteamLibrary\steamapps\common\Software Inc"
)

$ErrorActionPreference = "Stop"
$managed = Join-Path $GameDir "Software Inc_Data\Managed"
Add-Type -Path (Join-Path $managed "Mono.Cecil.dll")

$resolver = New-Object Mono.Cecil.DefaultAssemblyResolver
$resolver.AddSearchDirectory($managed)
$params = New-Object Mono.Cecil.ReaderParameters
$params.AssemblyResolver = $resolver
$asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $managed "Assembly-CSharp.dll"), $params)

$all = New-Object System.Collections.Generic.List[object]
function Walk($t) { $script:all.Add($t); foreach ($n in $t.NestedTypes) { Walk $n } }
foreach ($t in $asm.MainModule.Types) { Walk $t }

if ($Find) {
    $all | Where-Object { $_.FullName -match $Find -and $_.Name -notmatch '^<' -and $_.FullName -notmatch '/<' } |
        ForEach-Object { $_.FullName }
    return
}

if (-not $Type) { throw "Give -Type <name> or -Find <regex>" }

$t = $all | Where-Object { $_.FullName -eq $Type -or $_.Name -eq $Type } | Select-Object -First 1
if (-not $t) { throw "Type '$Type' not found (use -Find to search)" }

$kind = 'class'
if ($t.IsEnum) { $kind = 'enum' } elseif ($t.IsInterface) { $kind = 'interface' }
"$kind $($t.FullName) : $($t.BaseType.Name)"

if ($t.IsEnum) {
    $t.Fields | Where-Object { $_.Name -ne 'value__' } | ForEach-Object { "  $($_.Name) = $($_.Constant)" }
    return
}

$lines = @()
$lines += $t.Fields | Where-Object { $_.Name -notmatch '^<' } | ForEach-Object {
    $vis = if ($_.IsPublic) { 'public' } else { 'private' }
    $st = if ($_.IsStatic) { ' static' } else { '' }
    "F  $vis$st $($_.FieldType.Name) $($_.Name)"
}
$lines += $t.Properties | ForEach-Object { "P  $($_.PropertyType.Name) $($_.Name)" }
$lines += $t.Methods | Where-Object { -not $_.IsSpecialName -and $_.Name -notmatch '^<' } | ForEach-Object {
    $vis = if ($_.IsPublic) { 'public' } else { 'private' }
    $st = if ($_.IsStatic) { ' static' } else { '' }
    $ps = ($_.Parameters | ForEach-Object { "$($_.ParameterType.Name) $($_.Name)" }) -join ', '
    "M  $vis$st $($_.ReturnType.Name) $($_.Name)($ps)"
}
$lines += $t.Events | ForEach-Object { "E  $($_.EventType.Name) $($_.Name)" }
$lines | Where-Object { $_ -match $Match } | Sort-Object -Unique | ForEach-Object { "  $_" }
