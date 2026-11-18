# Purpose: Add-UniqueString - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Adds unique String for the calling workflow.
function Add-UniqueString {
    param(
        [System.Collections.Generic.List[string]]$List,

        [string]$Value
    )

    if ($null -eq $List) {
        return
    }

    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        if (-not $List.Contains($Value)) {
            $List.Add($Value) | Out-Null
        }
    }
}
