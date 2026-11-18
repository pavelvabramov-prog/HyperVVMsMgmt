# Purpose: Get-StorageRootForCompare - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Retrieves storage Root For Compare for the calling workflow.
function Get-StorageRootForCompare {
    param([AllowNull()][string]$PathValue)

    if ([string]::IsNullOrWhiteSpace($PathValue)) { return $null }

    $candidate = $PathValue.Trim()

    try {
        if ($candidate -match '^[Cc]:\ClusterStorage\([^\/]+)(?:[\/].*)?$') {
            return ("C:\ClusterStorage\{0}" -f $matches[1]).TrimEnd('\')
        }

        $root = [System.IO.Path]::GetPathRoot($candidate)
        if (-not [string]::IsNullOrWhiteSpace($root)) {
            return $root.TrimEnd('\')
        }
    }
    catch {
    }

    return $null
}
