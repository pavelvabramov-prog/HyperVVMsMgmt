# Purpose: Get-ResolvedDiskLayout - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Retrieves resolved Disk Layout for the calling workflow.
function Get-ResolvedDiskLayout {
    param(
        [Parameter(Mandatory = $true)][string]$BaseVMName,
        [Parameter(Mandatory = $true)][string]$DestinationRoot,
        [Parameter(Mandatory = $true)][string]$Letter,
        [AllowNull()][string]$DiskSubfolder,
        [AllowNull()][string]$DestinationOverride,
        [AllowNull()][string]$InPlacePath,
        [AllowNull()][string]$FolderNameOverride
    )

    $effectiveName = if ([string]::IsNullOrWhiteSpace($FolderNameOverride)) { $BaseVMName } else { $FolderNameOverride.Trim() }
    $vmRootPath = Join-Path -Path $DestinationRoot -ChildPath $effectiveName
    $normalizedSubfolder = Get-NormalizedDiskSubfolder -VDisksFolder $DiskSubfolder

    if (-not [string]::IsNullOrWhiteSpace($InPlacePath)) {
        $diskPath = $InPlacePath.Trim()
        $diskRootPath = Split-Path -Path $diskPath -Parent
        return [pscustomobject]@{
            Letter              = $Letter
            EffectiveRoot       = $diskRootPath
            VmRootPath          = $vmRootPath
            DiskRootPath        = $diskRootPath
            DiskPath            = $diskPath
            DiskSubfolder       = $null
            DestinationOverride = $null
            InPlacePath         = $diskPath
            IsOverrideExactPath = $false
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($DestinationOverride)) {
        $diskPath = $DestinationOverride.Trim()
        $diskRootPath = Split-Path -Path $diskPath -Parent
        return [pscustomobject]@{
            Letter              = $Letter
            EffectiveRoot       = $diskRootPath
            VmRootPath          = $vmRootPath
            DiskRootPath        = $diskRootPath
            DiskPath            = $diskPath
            DiskSubfolder       = $null
            DestinationOverride = $diskPath
            InPlacePath         = $null
            IsOverrideExactPath = $true
        }
    }

    $diskRootPath = if ($null -ne $normalizedSubfolder) { Join-Path -Path $vmRootPath -ChildPath $normalizedSubfolder } else { $vmRootPath }
    $diskPath = Join-Path -Path $diskRootPath -ChildPath "${BaseVMName}_${Letter}.vhdx"

    [pscustomobject]@{
        Letter              = $Letter
        EffectiveRoot       = $DestinationRoot
        VmRootPath          = $vmRootPath
        DiskRootPath        = $diskRootPath
        DiskPath            = $diskPath
        DiskSubfolder       = $normalizedSubfolder
        DestinationOverride = $DestinationOverride
        InPlacePath         = $null
        IsOverrideExactPath = $false
    }
}
