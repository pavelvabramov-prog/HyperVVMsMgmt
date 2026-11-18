# Purpose: Test-PathStringSegments - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Checks path String Segments for the calling workflow.
function Test-PathStringSegments {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)][string]$FieldLabel,
        [System.Collections.ArrayList]$Errors
    )

    try {
        foreach ($segment in ($PathValue -split '[\\/]')) {
            if ([string]::IsNullOrWhiteSpace($segment)) { continue }
            if ($segment -match '^[A-Za-z]:$') { continue }
            foreach ($invalidChar in [IO.Path]::GetInvalidFileNameChars()) {
                if ($segment.Contains([string]$invalidChar)) {
                    [void]$Errors.Add("$FieldLabel contains invalid path character '$invalidChar' in segment '$segment'.")
                    break
                }
            }
        }
    }
    catch {
        [void]$Errors.Add("Could not validate $FieldLabel. $($_.Exception.Message)")
    }
}
