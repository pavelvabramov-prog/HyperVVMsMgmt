# Purpose: Get-DerivedComputerName - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Retrieves derived Computer Name for the calling workflow.
function Get-DerivedComputerName {
    param([string]$VMName)

    $name = $VMName.Trim()

    if ([string]::IsNullOrWhiteSpace($name)) {
        throw "Could not derive computer name from VM Name '$VMName'"
    }

    return $name
}
