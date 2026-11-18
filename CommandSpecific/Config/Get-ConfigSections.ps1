# Purpose: Get-ConfigSections - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Retrieves config Sections for the calling workflow.
function Get-ConfigSections {
    param([string]$Path)
    Read-HVConfigGuestSections -Path $Path
}
