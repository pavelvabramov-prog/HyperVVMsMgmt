# Purpose: Get-TagsFromNotes - shared helper.
# Maintains the existing validation, logging, and execution behavior.

# Extracts structured Tags from Hyper-V VM Notes.
function Get-TagsFromNotes {
    param (
        [AllowEmptyString()]
        [string]$Notes
    )

    if ([string]::IsNullOrWhiteSpace($Notes)) {
        return @()
    }

    $TagLines = @(
        $Notes -split '\r?\n' |
            Where-Object { $_ -match '^\s*TAGS\s*=' }
    )

    if ($TagLines.Count -eq 0) {
        return @()
    }

    $TagString = (
        $TagLines[0] -replace '^\s*TAGS\s*=\s*', ''
    ).Trim()

    if ([string]::IsNullOrWhiteSpace($TagString)) {
        return @()
    }

    return @(
        ConvertTo-HVOrderedTags `
            -Tags ($TagString -split ';')
    )
}

