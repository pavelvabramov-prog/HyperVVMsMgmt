# Purpose: Test-Boundary - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Checks boundary for the calling workflow.
function Test-Boundary {
    param([string]$Base,[string]$Candidate)
    if ([string]::IsNullOrWhiteSpace($Base) -or [string]::IsNullOrWhiteSpace($Candidate)) { return $false }
    $escaped = [regex]::Escape($Base)
    return [regex]::IsMatch($Candidate, "(?i)(^|[^A-Za-z0-9])$escaped($|[^A-Za-z0-9])")
}
