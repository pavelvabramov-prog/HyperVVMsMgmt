# Purpose: Get-NormalizedDiskSubfolder - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Retrieves normalized Disk Subfolder for the calling workflow.
function Get-NormalizedDiskSubfolder {
    param([AllowNull()][string]$VDisksFolder)

    if ([string]::IsNullOrWhiteSpace($VDisksFolder)) { return $null }

    $normalized = $VDisksFolder.Trim()
    while ($normalized.StartsWith('\') -or $normalized.StartsWith('/')) { $normalized = $normalized.Substring(1) }
    while ($normalized.EndsWith('\') -or $normalized.EndsWith('/')) { $normalized = $normalized.Substring(0, $normalized.Length - 1) }
    if ([string]::IsNullOrWhiteSpace($normalized)) { return $null }
    $normalized
}
