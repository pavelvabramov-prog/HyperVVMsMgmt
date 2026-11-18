# Purpose: Get-HVDisplayVMName - shared helper.
# Maintains the existing validation, logging, and execution behavior.

# Retrieves hVDisplay VMName for the calling workflow.
function Get-HVDisplayVMName {
    param(
        [Parameter(Mandatory = $true)][string]$BaseVMName,
        [AllowNull()][string]$VMDescription,
        [switch]$ConfigDescriptionStyle
    )
    if ($ConfigDescriptionStyle) {
        if ([string]::IsNullOrWhiteSpace($VMDescription)) { return $BaseVMName.Trim() }
        return ('{0} - {1}' -f $BaseVMName.Trim(), $VMDescription.Trim())
    }
    if ([string]::IsNullOrWhiteSpace($VMDescription)) { return $BaseVMName }
    "$BaseVMName $($VMDescription.TrimStart())"
}
