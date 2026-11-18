# Purpose: Get-OptionalInt - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Retrieves optional Int for the calling workflow.
function Get-OptionalInt {
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    [int]$Value
}
