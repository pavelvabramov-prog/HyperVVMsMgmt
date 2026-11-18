# Purpose: Get-TargetDisplayVMName - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Retrieves target Display VMName for the calling workflow.
function Get-TargetDisplayVMName {
    param([string]$BaseVMName, [string]$VMDescription)
    Get-HVDisplayVMName -BaseVMName $BaseVMName -VMDescription $VMDescription -ConfigDescriptionStyle
}
