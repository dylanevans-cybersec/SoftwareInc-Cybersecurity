# Structural linter for this mod's TyD files.
# Usage: powershell -File tools\lint-tyd.ps1 [-Root <project root>] [-Quiet]
# Exit code 1 if any error is found (warnings do not fail).
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "TydParser.ps1")

$script:errors = 0
$script:warnings = 0
function Err($file, $msg)  { $script:errors++;   Write-Host "ERROR   $file : $msg" -ForegroundColor Red }
function Warn($file, $msg) { $script:warnings++; Write-Host "warning $file : $msg" -ForegroundColor Yellow }

# Values from the Data Modding wiki
$builtInThumbs = @('Camera','Console','Fingerprint','Gyroscope','Harddrive','Joystick','LCD','Microchip','PCB','Phone','Plastic','PlasticCase','Speaker','Thermostat','Touch','USB','Battery','Antenna','LED','Vibration','Unknown')
# Software types in the base game (extracted from resources.assets, see docs/catalog.md)
$vanillaTypes = @('Distribution platform','Operating System','Game','3D Editor','Antivirus','Embedded System','Game Assets','Audio Tool','2D Editor','Website','Office Software','Logistics Application')

# The leading comma stops PowerShell from unrolling lists on return.
function Get-Table($t, $key) { if ($t -is [System.Collections.IDictionary] -and $t.Contains($key)) { return , $t[$key] } return $null }
function Get-List($t, $key) {
    $v = Get-Table $t $key
    if ($v -is [System.Collections.Generic.List[object]]) { return , $v.ToArray() }
    return , (New-Object object[] 0)
}
# @($list) throws "Argument types do not match" on List[object] in Windows PowerShell 5.1, so convert explicitly.
function To-Array($v) {
    if ($null -eq $v) { return , (New-Object object[] 0) }
    if ($v -is [System.Collections.Generic.List[object]]) { return , $v.ToArray() }
    $a = New-Object object[] 1
    $a[0] = $v
    return , $a
}
function Is-Number($s) { $d = 0.0; return [double]::TryParse([string]$s, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d) }
function Num($s) { return [double]::Parse([string]$s, [Globalization.CultureInfo]::InvariantCulture) }

function Check-Submarkets($file, $where, $tbl, $allowScalarZero) {
    $sm = Get-Table $tbl 'Submarkets'
    if ($null -eq $sm) { return }
    if ($sm -is [System.Collections.Generic.List[object]]) {
        if ($sm.Count -ne 3) { Err $file "$where : Submarkets needs exactly 3 values (has $($sm.Count))" }
        foreach ($v in $sm) { if (-not (Is-Number $v)) { Err $file "$where : Submarkets value '$v' is not a number" } }
    } elseif ($sm -eq '0' -and $allowScalarZero) {
        # fine: level 3 features use "Submarkets 0"
    } else {
        Err $file "$where : Submarkets must be a list of 3 numbers (scalar 0 is only valid on level 3 features)"
    }
}

function Check-Number($file, $where, $tbl, $key, $min, $max) {
    $v = Get-Table $tbl $key
    if ($null -eq $v) { return }
    if (-not (Is-Number $v)) { Err $file "$where : $key '$v' is not a number"; return }
    $d = Num $v
    if ($d -lt $min -or $d -gt $max) { Warn $file "$where : $key $d outside expected range $min..$max" }
}

function Collect-Features($list, $acc) {
    foreach ($f in $list) {
        if ($f -isnot [System.Collections.IDictionary]) { continue }
        $acc.Add($f)
        Collect-Features (Get-List $f 'Features') $acc
    }
}

# Does a feature's SoftwareCategories list include this category? (No list = all categories.)
function Applies($feature, $catName) {
    $sc = Get-Table $feature 'SoftwareCategories'
    if ($null -eq $sc) { return $true }
    foreach ($e in (To-Array $sc)) {
        if ($e -is [System.Collections.Generic.List[object]]) { if ($e.Count -gt 0 -and $e[0] -eq $catName) { return $true } }
        elseif ($e -eq $catName) { return $true }
    }
    return $false
}

# The game refuses to load a mod when a manufacturing component depends on a feature that does not exist
# in one of the categories using that manufacturing block ("depends on a feature that has an incompatible category").
function Check-MfgCategories($file, $typeName, $mf, $catNames, $st) {
    $index = @{}
    foreach ($sf in (Get-List $st 'Features')) {
        $sn = Get-Table $sf 'Name'; if ($sn) { $index[$sn] = @{ Spec = $sf; Sub = $null } }
        foreach ($sub in (Get-List $sf 'Features')) { $n = Get-Table $sub 'Name'; if ($n) { $index[$n] = @{ Spec = $sf; Sub = $sub } } }
    }
    foreach ($c in (Get-List $mf 'Components')) {
        $dep = Get-Table $c 'DependsOn'
        if (-not $dep -or -not $index.ContainsKey($dep)) { continue }
        $e = $index[$dep]
        foreach ($cn in $catNames) {
            $ok = Applies $e.Spec $cn
            # sub-features only self-restrict when the spec feature has no restriction of its own
            if ($ok -and $e.Sub -and ($null -eq (Get-Table $e.Spec 'SoftwareCategories'))) { $ok = Applies $e.Sub $cn }
            if (-not $ok) { Err $file "$typeName/$cn : Manufacturing component '$(Get-Table $c 'Name')' depends on feature '$dep', which is not available in category '$cn'" }
        }
    }
}

function Check-Manufacturing($file, $mf, $featureNames) {
    $where = 'Manufacturing'
    $comps = Get-List $mf 'Components'
    $procs = Get-List $mf 'Processes'
    if ($comps.Count -eq 0) { Err $file "$where : no Components"; return }
    if ($procs.Count -eq 0) { Err $file "$where : no Processes"; return }

    $names = @{}
    foreach ($c in $comps) {
        $n = Get-Table $c 'Name'
        if (-not $n) { Err $file "$where : component without Name"; continue }
        if ($names.ContainsKey($n)) { Err $file "$where : duplicate component '$n'" }
        $names[$n] = $true
        $bt = Get-Table $c 'BuiltInThumbnail'
        $th = Get-Table $c 'Thumbnail'
        if ($bt -and ($builtInThumbs -notcontains $bt)) { Err $file "$where : component '$n' has unknown BuiltInThumbnail '$bt'" }
        if (-not $bt -and -not $th) { Warn $file "$where : component '$n' has no thumbnail (shows Unknown)" }
        Check-Number $file "$where/$n" $c 'Price' 0 100000
        Check-Number $file "$where/$n" $c 'Time' 0 1000
        $dep = Get-Table $c 'DependsOn'
        if ($dep -and $featureNames -notcontains $dep) { Err $file "$where : component '$n' DependsOn unknown feature '$dep'" }
    }

    $asInput = @{}; $asOutput = @{}; $finals = 0
    foreach ($p in $procs) {
        foreach ($i in (Get-List $p 'Inputs')) {
            if (-not $names.ContainsKey($i)) { Err $file "$where : process input '$i' is not a component" }
            if ($asInput.ContainsKey($i)) { Err $file "$where : component '$i' is an input in more than one process" }
            $asInput[$i] = $true
        }
        $o = Get-Table $p 'Output'
        if ($o -eq 'Final') { $finals++ }
        elseif (-not $names.ContainsKey($o)) { Err $file "$where : process output '$o' is not a component" }
        else {
            if ($asOutput.ContainsKey($o)) { Err $file "$where : component '$o' is the output of more than one process" }
            $asOutput[$o] = $true
        }
    }
    if ($finals -ne 1) { Err $file "$where : exactly one process must output Final (found $finals)" }
    foreach ($n in $names.Keys) {
        if (-not $asInput.ContainsKey($n) -and -not $asOutput.ContainsKey($n)) { Warn $file "$where : component '$n' is unused" }
    }
}

function Check-SoftwareType($file, $st, $allTypeNames) {
    $name = Get-Table $st 'Name'
    if (-not $name) { Err $file "SoftwareType has no Name"; return }
    if ((Get-Table $st 'Override') -eq 'Delete') { return }   # "Override Delete" removes a vanilla type; nothing else to check
    $override = (Get-Table $st 'Override') -eq 'True'

    if (Get-Table $st 'Category') { Warn $file "$name : 'Category' is deprecated since Beta 1, use 'Categories'" }

    $sn = Get-Table $st 'SubmarketNames'
    if ($sn -is [System.Collections.Generic.List[object]]) {
        if ($sn.Count -ne 3) { Err $file "$name : SubmarketNames needs exactly 3 names (has $($sn.Count))" }
    } elseif (-not $override) {
        Err $file "$name : SubmarketNames missing (needs exactly 3 names)"
    }

    $cats = Get-List $st 'Categories'
    $catNames = @{}
    foreach ($c in $cats) {
        $cn = Get-Table $c 'Name'
        if (-not $cn) { Err $file "$name : category without Name"; continue }
        if ($catNames.ContainsKey($cn)) { Err $file "$name : duplicate category '$cn'" }
        $catNames[$cn] = $true
        Check-Submarkets $file "$name/$cn" $c $false
        Check-Number $file "$name/$cn" $c 'Popularity' 0 1
        Check-Number $file "$name/$cn" $c 'TimeScale' 0 1   # wiki: "between 0 and 1"
        Check-Number $file "$name/$cn" $c 'Iterative' 0 1
        Check-Number $file "$name/$cn" $c 'Unlock' 1970 2100
    }

    # Wiki: "You may have only one SpecFeature per specialization"
    $specsSeen = @{}
    foreach ($sf in (Get-List $st 'Features')) {
        $sp = Get-Table $sf 'Spec'
        if (-not $sp) { if (-not $override) { Warn $file "$name : top-level feature '$(Get-Table $sf 'Name')' has no Spec" }; continue }
        if (@('System','Network','2D','3D','Audio','Hardware') -notcontains $sp) { Err $file "$name : Spec '$sp' is not provided by any vanilla Operating System, so the game rejects the mod (only System, Network, 2D, 3D, Audio, Hardware work)" }
        if ($specsSeen.ContainsKey($sp)) { Err $file "$name : two top-level features use Spec '$sp' (only one SpecFeature per specialization)" }
        $specsSeen[$sp] = $true
    }

    $feats = New-Object System.Collections.Generic.List[object]
    Collect-Features (Get-List $st 'Features') $feats
    $featureNames = @()
    $seen = @{}
    foreach ($f in $feats) {
        $fn = Get-Table $f 'Name'
        if (-not $fn) { Err $file "$name : feature without Name"; continue }
        $featureNames += $fn
        if ($seen.ContainsKey($fn)) { Err $file "$name : duplicate feature name '$fn'" }
        $seen[$fn] = $true
        $lvl = Get-Table $f 'Level'
        $isLevel3 = ($lvl -eq '3')
        Check-Submarkets $file "$name/$fn" $f $isLevel3
        Check-Number $file "$name/$fn" $f 'DevTime' 0 40
        Check-Number $file "$name/$fn" $f 'CodeArt' 0 1
        # Vanilla uses 0.0001-0.0005 (Antivirus, OS) and 0.002 for MMO; anything much higher needs huge server capacity
        Check-Number $file "$name/$fn" $f 'Server' 0 0.005
        Check-Number $file "$name/$fn" $f 'Unlock' 1970 2100
        if ($lvl) { Check-Number $file "$name/$fn" $f 'Level' 1 3 }
        if ($isLevel3 -and -not ((Get-Table $f 'Script_EndOfDay') -or (Get-Table $f 'Script_AfterSales') -or (Get-Table $f 'Script_OnRelease') -or (Get-Table $f 'Script_NewCopies') -or (Get-Table $f 'Script_WorkItemChange'))) {
            Warn $file "$name/$fn : level 3 feature has no script"
        }
        foreach ($e in (To-Array (Get-Table $f 'SoftwareCategories'))) {
            $refName = $e
            if ($e -is [System.Collections.Generic.List[object]]) { $refName = $e[0] }
            if ($refName -and $catNames.Count -gt 0 -and -not $catNames.ContainsKey($refName)) { Err $file "$name/$fn : SoftwareCategories names '$refName', which is not a category of this type" }
        }
        $dep = Get-Table $f 'Dependencies'
        if ($dep -and $lvl) { Err $file "$name/$fn : 'Dependencies' is only documented on spec features, not sub-features (Level $lvl)" }
        foreach ($d in (To-Array $dep)) {
            if ($allTypeNames -notcontains $d -and $vanillaTypes -notcontains $d) {
                Warn $file "$name/$fn : Dependencies '$d' is not a software type known to this mod or the vanilla list"
            }
        }
    }

    # Balance: vanilla OptimalDevTime is about half of the summed feature DevTime (Antivirus 25/45, OS 75/~150).
    # If it exceeds the total, 100% submarket satisfaction is unreachable (wiki: TEST_DEV_MOD).
    $odt = Get-Table $st 'OptimalDevTime'
    if ($odt -and (Is-Number $odt) -and $feats.Count -gt 0) {
        $total = 0.0
        foreach ($f in $feats) { $d = Get-Table $f 'DevTime'; if ($d -and (Is-Number $d)) { $total += (Num $d) } }
        $ratio = (Num $odt) / $total
        if ($cats.Count -gt 0) {
            # With variants, only the per-category check below matters (category-only features inflate the type-wide total).
            if (-not $Quiet) { Write-Host "  info  $name : OptimalDevTime $odt (type-wide DevTime $total)" -ForegroundColor DarkGray }
        }
        elseif ($ratio -gt 0.8) { Warn $file "$name : OptimalDevTime $odt vs total feature DevTime $total (ratio $([math]::Round($ratio,2))) - 100% may be unreachable" }
        elseif ($ratio -lt 0.3) { Warn $file "$name : OptimalDevTime $odt vs total feature DevTime $total (ratio $([math]::Round($ratio,2))) - very easy to max out" }
        elseif (-not $Quiet) { Write-Host "  info  $name : OptimalDevTime $odt / total DevTime $total (ratio $([math]::Round($ratio,2)))" -ForegroundColor DarkGray }
    }

    # Same check per category: features restricted with SoftwareCategories only count for the listed categories.
    # A spec feature's SoftwareCategories override its sub-features' own (wiki), so sub-features only self-restrict when the spec feature has none.
    if ($odt -and (Is-Number $odt) -and $cats.Count -gt 0) {
        foreach ($c in $cats) {
            $cn = Get-Table $c 'Name'
            $ctotal = 0.0
            foreach ($sf in (Get-List $st 'Features')) {
                if (-not (Applies $sf $cn)) { continue }
                $d = Get-Table $sf 'DevTime'; if ($d -and (Is-Number $d)) { $ctotal += (Num $d) }
                $parentRestricts = ($null -ne (Get-Table $sf 'SoftwareCategories'))
                foreach ($sub in (Get-List $sf 'Features')) {
                    if (-not $parentRestricts -and -not (Applies $sub $cn)) { continue }
                    $d = Get-Table $sub 'DevTime'; if ($d -and (Is-Number $d)) { $ctotal += (Num $d) }
                }
            }
            if ($ctotal -le 0) { continue }
            $cr = (Num $odt) / $ctotal
            if ($cr -gt 0.8) { Warn $file "$name/$cn : OptimalDevTime $odt vs category feature DevTime $ctotal (ratio $([math]::Round($cr,2))) - 100% may be unreachable" }
            elseif (-not $Quiet) { Write-Host "    cat   $name/$cn : DevTime $ctotal (ratio $([math]::Round($cr,2)))" -ForegroundColor DarkGray }
        }
    }

    foreach ($a in (Get-List $st 'AddOns')) {
        $an = Get-Table $a 'Name'
        $afeats = New-Object System.Collections.Generic.List[object]
        Collect-Features (Get-List $a 'Features') $afeats
        foreach ($f in $afeats) {
            $fn = Get-Table $f 'Name'
            Check-Submarkets $file "$name/AddOn $an/$fn" $f ((Get-Table $f 'Level') -eq '3')
            if ($fn) { $featureNames += $fn }
        }
    }

    $hw = (Get-Table $st 'Hardware') -eq 'True'
    $mfRoot = Get-Table $st 'Manufacturing'
    if ($hw -and -not $mfRoot) {
        $allCatsHave = ($cats.Count -gt 0)
        foreach ($c in $cats) { if (-not (Get-Table $c 'Manufacturing')) { $allCatsHave = $false } }
        if (-not $allCatsHave) { Err $file "$name : Hardware True but no Manufacturing (on the type or on every category)" }
    }
    $allCatNames = @(); foreach ($c in $cats) { $allCatNames += (Get-Table $c 'Name') }
    if ($mfRoot) {
        Check-Manufacturing $file $mfRoot $featureNames
        Check-MfgCategories $file $name $mfRoot $allCatNames $st
    }
    foreach ($c in $cats) {
        $m = Get-Table $c 'Manufacturing'
        if ($m) {
            Check-Manufacturing $file $m $featureNames
            Check-MfgCategories $file $name $m @((Get-Table $c 'Name')) $st
        }
    }
}

function Check-Furniture($file, $root, $dir) {
    $fu = Get-Table $root 'Furniture'
    $name = Get-Table $fu 'Name'
    if (-not $name) { Err $file "Furniture has no Name"; return }
    $comp = Get-Table $fu 'Furniture'
    if (-not (Get-Table $comp 'LocalizedName')) { Warn $file "$name : no Furniture.LocalizedName" }
    $th = Get-Table $fu 'Thumbnail'
    if (-not $th) { Err $file "$name : no Thumbnail"; return }
    $thPath = Join-Path $dir $th
    if (-not (Test-Path $thPath)) { Err $file "$name : Thumbnail '$th' not found"; return }
    try {
        Add-Type -AssemblyName System.Drawing
        $img = [System.Drawing.Image]::FromFile($thPath)
        if ($img.Width -ne 128 -or $img.Height -ne 128) { Err $file "$name : Thumbnail must be 128x128 (is $($img.Width)x$($img.Height))" }
        $img.Dispose()
    } catch { Warn $file "$name : could not read thumbnail size ($($_.Exception.Message))" }
}

# ---- gather -----------------------------------------------------------------
# The data mod lives inside the code mod folder (registered by the code at startup).
$modDir = Join-Path $Root 'DLLMods\Cybersecurity\Data'
$furnDir = Join-Path $Root 'Furniture\Cybersecurity'   # furniture was abandoned; only checked if the folder exists

$parsed = @{}
$files = @()
foreach ($d in @($modDir, $furnDir)) {
    if (Test-Path $d) { $files += Get-ChildItem $d -Recurse -Filter *.tyd -File }
}
foreach ($f in $files) {
    $rel = $f.FullName.Substring($Root.Length + 1)
    try { $parsed[$f.FullName] = ConvertFrom-Tyd -Text (Get-Content $f.FullName -Raw) }
    catch { Err $rel $_.Exception.Message }
}

$allTypeNames = @()
foreach ($k in $parsed.Keys) {
    $st = Get-Table $parsed[$k] 'SoftwareType'
    if ($st) { $n = Get-Table $st 'Name'; if ($n) { $allTypeNames += $n } }
}
$dupTypes = $allTypeNames | Group-Object | Where-Object { $_.Count -gt 1 }
foreach ($d in $dupTypes) { Err 'mod' "software type '$($d.Name)' is defined in more than one file" }

$furnNames = @{}
foreach ($k in $parsed.Keys) {
    $rel = $k.Substring($Root.Length + 1)
    $r = $parsed[$k]
    $st = Get-Table $r 'SoftwareType'
    if ($st) { Check-SoftwareType $rel $st $allTypeNames }

    $ct = Get-Table $r 'CompanyType'
    if ($ct) {
        if (-not (Get-Table $ct 'Specialization')) { Err $rel "CompanyType has no Specialization" }
        foreach ($t in (Get-List $ct 'Types')) {
            $sw = Get-Table $t 'Software'
            if ($sw -and $allTypeNames -notcontains $sw -and $vanillaTypes -notcontains $sw) { Warn $rel "CompanyType makes unknown software '$sw'" }
        }
    }

    if (Get-Table $r 'Furniture') {
        Check-Furniture $rel $r (Split-Path -Parent $k)
        $fn = Get-Table (Get-Table $r 'Furniture') 'Name'
        if ($fn) { if ($furnNames.ContainsKey($fn)) { Err $rel "furniture Name '$fn' also used in $($furnNames[$fn])" } else { $furnNames[$fn] = $rel } }
    }
}

# NameGenerators referenced by SoftwareTypes must exist
$gens = @{}
if (Test-Path (Join-Path $modDir 'NameGenerators')) {
    Get-ChildItem (Join-Path $modDir 'NameGenerators') -Filter *.txt | ForEach-Object { $gens[$_.BaseName] = $true }
}
foreach ($k in $parsed.Keys) {
    $rel = $k.Substring($Root.Length + 1)
    $st = Get-Table $parsed[$k] 'SoftwareType'
    if (-not $st) { continue }
    $refs = @()
    $g = Get-Table $st 'NameGenerator'; if ($g) { $refs += $g }
    foreach ($c in (Get-List $st 'Categories')) { $g = Get-Table $c 'NameGenerator'; if ($g) { $refs += $g } }
    foreach ($a in (Get-List $st 'AddOns')) { $g = Get-Table $a 'NameGenerator'; if ($g) { $refs += $g } }
    foreach ($r in ($refs | Select-Object -Unique)) { if (-not $gens.ContainsKey($r)) { Warn $rel "NameGenerator '$r' has no NameGenerators/$r.txt in this mod (fine if it is a vanilla generator)" } }
}

if (-not $Quiet) {
    Write-Host ""
    Write-Host "$($files.Count) file(s) checked: $script:errors error(s), $script:warnings warning(s)"
}
if ($script:errors -gt 0) { exit 1 }
