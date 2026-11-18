# Purpose: ConvertTo-NormalizedTags - shared helper.
# Maintains the existing validation, logging, and execution behavior.

# Normalizes tag input for consistent validation and comparison.
function ConvertTo-NormalizedTags {
    param([string[]]$InputTags)
    $seen = @{}
    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($item in @($InputTags)) {
        if ($null -eq $item) { continue }
        $tag = $item.Trim()
        if (-not $tag) { continue }
        if (-not $seen.ContainsKey($tag)) { $seen[$tag] = $true; $result.Add($tag) }
    }
    return @($result.ToArray())
}
# Checks parsed tags against approved categories and values.
function Test-ApprovedTags {
    param([string[]]$InputTags,[hashtable]$Catalog,[switch]$AllowCustomTags,[switch]$AllowLegacyForRemoval)
    $errors = @()
    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($tag in @(ConvertTo-NormalizedTags $InputTags)) {
        if ($tag -notmatch '^([A-Za-z][A-Za-z0-9_]*):(.+)$') {
            if ($AllowLegacyForRemoval) { $result.Add($tag); continue }
            $errors += "Invalid CATEGORY:VALUE tag '$tag'"
            continue
        }
        $category = $Matches[1]
        $canonical = @{ SCOPE="Scope"; ENV="Env"; APP="App"; ROLE="Role"; CONTACT="Contact" }
        $categoryKey = $category.ToUpperInvariant()
        if ($canonical.ContainsKey($categoryKey)) { $category = $canonical[$categoryKey] }
        $value = $Matches[2].Trim()
        if (-not $value -or $value.Contains(';')) { $errors += "Invalid value in '$tag'"; continue }
        if ($AllowLegacyForRemoval) { $result.Add("${category}:$value"); continue }
        if (-not $Catalog.ContainsKey($categoryKey)) {
            if (-not $AllowCustomTags) { $errors += "Unapproved category '$category'"; continue }
        }
        elseif (-not $Catalog[$categoryKey].AllowCustom -and -not $Catalog[$categoryKey].Values.ContainsKey($value) -and -not $AllowCustomTags) {
            $errors += "Unapproved value '$value' in $category"; continue
        }
        elseif ($Catalog[$categoryKey].Values.ContainsKey($value)) {
            $value = $Catalog[$categoryKey].Values[$value]
        }
        $result.Add("${category}:$value")
    }
    if ($errors.Count) { throw ($errors -join '; ') }
    return @($result.ToArray())
}


# Tag categories are literal. No translation between old and new names.
function ConvertTo-HVOrderedTags {
    param([string[]]$Tags)
    $ErrorActionPreference = 'Stop'
    $priority = @('Scope','Env','App','Role','Contact')
    $unique = [System.Collections.Generic.Dictionary[string,string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($raw in @($Tags)) {
        if ($null -eq $raw) { continue }
        $tag = ([string]$raw).Trim()
        if ($tag -and -not $unique.ContainsKey($tag)) { $unique.Add($tag,$tag) }
    }
    return @($unique.Values | Sort-Object -Property @{Expression={
        $category = if ($_ -match '^([^:]+):') { $Matches[1] } else { '' }
        $index = [array]::IndexOf($priority, $category)
        if ($index -lt 0) { for ($j=0; $j -lt $priority.Count; $j++) { if ($priority[$j] -ieq $category) { $index = $j; break } } }
        if ($index -lt 0) { 100 } else { $index }
    }}, @{Expression={
        if ($_ -match '^([^:]+):') { $Matches[1].ToUpperInvariant() } else { 'ZZZ' }
    }}, @{Expression={
        if ($_ -match '^[^:]+:(.*)$') { $Matches[1].ToUpperInvariant() } else { $_.ToUpperInvariant() }
    }})
}
# Formats hVReadable Tags for the calling workflow.
function Format-HVReadableTags {
    param([string[]]$Tags)
    return (@(ConvertTo-HVOrderedTags $Tags) -join '; ')
}
# Checks hVTag Set Equal for the calling workflow.
function Test-HVTagSetEqual {
    param([string[]]$Left,[string[]]$Right)
    $a = @(ConvertTo-HVOrderedTags $Left)
    $b = @(ConvertTo-HVOrderedTags $Right)
    if ($a.Count -ne $b.Count) { return $false }
    for ($i=0;$i -lt $a.Count;$i++) { if ($a[$i] -ine $b[$i]) { return $false } }
    return $true
}
