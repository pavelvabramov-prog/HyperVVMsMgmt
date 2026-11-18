# Updates the Tags portion of VM Notes while retaining unrelated text.
function Set-TagsInNotes {
    param (
        [AllowEmptyString()]
        [string]$Notes,

        [string[]]$NewTags
    )

    $Lines = @()

    if (-not [string]::IsNullOrWhiteSpace($Notes)) {
        $Lines = @($Notes -split '\r?\n')
    }

    # Remove ALL existing TAGS= lines.
    $Lines = @(
        $Lines |
            Where-Object { $_ -notmatch '^\s*TAGS\s*=' }
    )

    # Remove trailing blank lines.
    while (
        $Lines.Count -gt 0 -and
        [string]::IsNullOrWhiteSpace($Lines[-1])
    ) {
        if ($Lines.Count -eq 1) {
            $Lines = @()
        }
        else {
            $Lines = @($Lines[0..($Lines.Count - 2)])
        }
    }

    if ($NewTags.Count -gt 0) {
        $TagLine = 'TAGS=' + (Format-HVReadableTags -Tags $NewTags)

        if ($Lines.Count -gt 0) {
            $Lines += ''
        }

        $Lines += $TagLine
    }

    return ($Lines -join [Environment]::NewLine)
}

