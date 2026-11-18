# Purpose: Normalize-PathForCompare - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Handles path For Compare for the calling workflow.
function Normalize-PathForCompare {
    param([AllowNull()][string]$PathValue)

    if ([string]::IsNullOrWhiteSpace($PathValue)) { return $null }

    try {
        $full = [System.IO.Path]::GetFullPath($PathValue.Trim())
        return $full.TrimEnd('\')
    }
    catch {
        return $PathValue.Trim().TrimEnd('\')
    }
}
