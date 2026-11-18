# Purpose: Get-TargetComputerName - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Retrieves target Computer Name for the calling workflow.
function Get-TargetComputerName {
    param(
        [string]$VMName,
        [string]$PCNameOverride
    )

    if (-not [string]::IsNullOrWhiteSpace($PCNameOverride)) {
        return $PCNameOverride.Trim()
    }

    return (Get-DerivedComputerName $VMName)
}
