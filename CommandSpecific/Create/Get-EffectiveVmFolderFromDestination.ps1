# Purpose: Get-EffectiveVmFolderFromDestination - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Retrieves effective Vm Folder From Destination for the calling workflow.
function Get-EffectiveVmFolderFromDestination {
    param(
        [AllowNull()][string]$DestinationRoot,
        [Parameter(Mandatory = $true)][string]$BaseVMName,
        [AllowNull()][string]$FolderNameOverride
    )

    if ([string]::IsNullOrWhiteSpace($DestinationRoot)) { return $null }

    try {
        return Normalize-PathForCompare -PathValue (Join-Path -Path $DestinationRoot.Trim() -ChildPath $(if ([string]::IsNullOrWhiteSpace($FolderNameOverride)) { $BaseVMName } else { $FolderNameOverride.Trim() }))
    }
    catch {
        return $null
    }
}
