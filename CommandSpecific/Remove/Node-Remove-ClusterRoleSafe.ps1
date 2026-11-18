# Purpose: Remove-ClusterRoleSafe - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Removes cluster Role Safe for the calling workflow.
function Remove-ClusterRoleSafe {
    param(
        [Parameter(Mandatory = $true)]
        $ClusterGroup
    )

    $removed = $false
    $details = @()

    try {
        Write-Info "Removing cluster role '$($ClusterGroup.Name)'..."

        try {
            Stop-ClusterGroup -Name $ClusterGroup.Name -Wait 30 -ErrorAction SilentlyContinue | Out-Null
        }
        catch {
        }

        try {
            Remove-ClusterGroup -Name $ClusterGroup.Name -RemoveResources -Force -ErrorAction Stop
            $removed = $true
            $details += "Cluster group '$($ClusterGroup.Name)' removed (with resources)."
        }
        catch {
            $details += "Primary cluster-group removal attempt failed: $($_.Exception.Message)"

            try {
                Remove-ClusterGroup -Name $ClusterGroup.Name -Force -ErrorAction Stop
                $removed = $true
                $details += "Cluster group '$($ClusterGroup.Name)' removed."
            }
            catch {
                $details += "Fallback cluster-group removal attempt failed: $($_.Exception.Message)"
                throw "Unable to remove cluster role '$($ClusterGroup.Name)'."
            }
        }
    }
    catch {
        throw
    }

    return [pscustomobject]@{
        Removed = $removed
        Details = $details
    }
}

