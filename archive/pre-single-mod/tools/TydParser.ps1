# Minimal TyD parser (dot-source this file).
#   ConvertFrom-Tyd -Text <string>  ->  ordered dictionary
# Tables become OrderedDictionary, lists become List[object], scalars become strings.
# Duplicate keys in one table are kept as "Key#2", "Key#3", ...

function Read-TydTokens {
    param([string]$Text)
    $tokens = New-Object System.Collections.Generic.List[object]
    $i = 0; $n = $Text.Length; $line = 1
    while ($i -lt $n) {
        $c = $Text[$i]
        if ($c -eq "`n") { $line++; $i++; continue }
        if ([char]::IsWhiteSpace($c)) { $i++; continue }

        if ($c -eq '#') {
            # "#RRGGBB" / "#RRGGBBAA" is a colour value, anything else is a comment
            $rest = $Text.Substring($i, [Math]::Min(10, $n - $i))
            if ($rest -match '^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?(\s|$)') {
                $len = ($rest -replace '\s.*$', '').Length
                $tokens.Add(@{ T = 'bare'; V = $Text.Substring($i, $len); L = $line })
                $i += $len
                continue
            }
            while ($i -lt $n -and $Text[$i] -ne "`n") { $i++ }
            continue
        }

        if ($c -eq '"') {
            $sb = New-Object System.Text.StringBuilder
            $startLine = $line
            $i++
            while ($i -lt $n -and $Text[$i] -ne '"') {
                if ($Text[$i] -eq '\' -and $i + 1 -lt $n) {
                    [void]$sb.Append($Text[$i + 1]); $i += 2; continue
                }
                if ($Text[$i] -eq "`n") { $line++ }
                [void]$sb.Append($Text[$i]); $i++
            }
            if ($i -ge $n) { throw "Unterminated string starting on line $startLine" }
            $i++
            $tokens.Add(@{ T = 'str'; V = $sb.ToString(); L = $startLine })
            continue
        }

        if ('{}[];'.Contains([string]$c)) {
            $tokens.Add(@{ T = 'punc'; V = [string]$c; L = $line })
            $i++
            continue
        }

        $start = $i
        while ($i -lt $n -and -not [char]::IsWhiteSpace($Text[$i]) -and -not '{}[];"#'.Contains([string]$Text[$i])) { $i++ }
        $tokens.Add(@{ T = 'bare'; V = $Text.Substring($start, $i - $start); L = $line })
    }
    return , $tokens
}

function ConvertFrom-Tyd {
    param([Parameter(Mandatory)][string]$Text)

    $script:tk = Read-TydTokens -Text $Text
    $script:p = 0

    function Parse-Value {
        if ($script:p -ge $script:tk.Count) { throw "Unexpected end of file (missing value)" }
        $t = $script:tk[$script:p]
        if ($t.T -eq 'punc') {
            if ($t.V -eq '{') { $script:p++; return (Parse-Table -Nested $true) }
            if ($t.V -eq '[') { $script:p++; return , (Parse-List) }
            throw "Line $($t.L): unexpected '$($t.V)' where a value was expected"
        }
        $script:p++
        return $t.V
    }

    function Parse-List {
        $list = New-Object System.Collections.Generic.List[object]
        while ($true) {
            if ($script:p -ge $script:tk.Count) { throw "Unexpected end of file inside a [ list ]" }
            $t = $script:tk[$script:p]
            if ($t.T -eq 'punc' -and $t.V -eq ']') { $script:p++; break }
            if ($t.T -eq 'punc' -and $t.V -eq ';') { $script:p++; continue }
            if ($t.T -eq 'punc' -and $t.V -eq '}') { throw "Line $($t.L): '}' inside a [ list ] (missing ']'?)" }
            $list.Add((Parse-Value))
        }
        return , $list
    }

    function Parse-Table {
        param([bool]$Nested)
        $tbl = New-Object System.Collections.Specialized.OrderedDictionary
        while ($true) {
            if ($script:p -ge $script:tk.Count) {
                if ($Nested) { throw "Unexpected end of file inside a { table } (missing '}')" }
                break
            }
            $t = $script:tk[$script:p]
            if ($t.T -eq 'punc') {
                if ($t.V -eq '}') {
                    if (-not $Nested) { throw "Line $($t.L): stray '}'" }
                    $script:p++; break
                }
                if ($t.V -eq ';') { $script:p++; continue }
                throw "Line $($t.L): unexpected '$($t.V)' where a key was expected"
            }
            $key = $t.V
            $script:p++
            $val = Parse-Value
            $k = $key; $dup = 2
            while ($tbl.Contains($k)) { $k = "$key#$dup"; $dup++ }
            $tbl[$k] = $val
        }
        return $tbl
    }

    return (Parse-Table -Nested $false)
}
