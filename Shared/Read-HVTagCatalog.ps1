# Purpose: Read-HVTagCatalog - shared helper.
# Maintains the existing validation, logging, and execution behavior.

# Loads the tag categories and allowed values from the tag configuration.
function Read-HVTagCatalog {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Tag catalog not found: $Path" }
    $catalog = @{}
    $section = $null
    $lineNumber = 0
    foreach ($line in (Get-Content -LiteralPath $Path -ErrorAction Stop)) {
        $lineNumber++
        $value = (($line -split '#',2)[0]).Trim()
        if (-not $value) { continue }
        if ($value -match '^\[([A-Za-z][A-Za-z0-9_]*)\]$') {
            $section = $Matches[1].ToUpperInvariant()
            if ($catalog.ContainsKey($section)) { throw "Duplicate category $section at catalog line $lineNumber" }
            $catalog[$section] = @{ Values = @{}; AllowCustom = $false }
            continue
        }
        if (-not $section) { throw "Value outside a category at catalog line $lineNumber" }
        if ($value -match '^ALLOW_CUSTOM\s*=\s*(YES|NO)$') {
            $catalog[$section].AllowCustom = ($Matches[1] -ieq 'YES')
            continue
        }
        if ($value -match '[=;:]') { throw "Invalid catalog value at line $lineNumber : $value" }
        if ($catalog[$section].Values.ContainsKey($value)) { throw "Duplicate catalog value at line $lineNumber : $value" }
        $catalog[$section].Values[$value] = $value
    }
    if ($catalog.Count -eq 0) { throw 'Tag catalog has no categories.' }
    return ,$catalog
}
