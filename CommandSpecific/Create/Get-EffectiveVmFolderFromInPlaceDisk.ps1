# Purpose: Get-EffectiveVmFolderFromInPlaceDisk - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Retrieves effective Vm Folder From In Place Disk for the calling workflow.
function Get-EffectiveVmFolderFromInPlaceDisk {
    param([AllowNull()][string]$InPlacePath)

    if ([string]::IsNullOrWhiteSpace($InPlacePath)) { return $null }

    try {
        return Normalize-PathForCompare -PathValue (Split-Path -Path $InPlacePath.Trim() -Parent)
    }
    catch {
        return $null
    }
}
