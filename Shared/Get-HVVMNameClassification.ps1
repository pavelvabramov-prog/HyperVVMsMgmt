# Purpose: Get-HVVMNameClassification - shared helper.
# Maintains the existing validation, logging, and execution behavior.

# Retrieves hVVMName Classification for the calling workflow.
function Get-HVVMNameClassification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ShortVMName,
        [Parameter(Mandatory)][string]$ExistingVMName
    )
    $short = $ShortVMName.Trim()
    $name = $ExistingVMName.Trim()
    if ([string]::IsNullOrWhiteSpace($short) -or [string]::IsNullOrWhiteSpace($name)) { return $null }
    if ($name.IndexOf($short, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return 'ShortNameMatch' }
    return $null
}
