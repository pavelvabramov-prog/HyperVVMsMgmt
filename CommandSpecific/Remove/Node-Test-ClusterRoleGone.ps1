# Purpose: Test-ClusterRoleGone - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Checks cluster Role Gone for the calling workflow.
function Test-ClusterRoleGone {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClusterGroupName
    )

    $remaining = @()

    try {
        $g = Get-ClusterGroup -Name $ClusterGroupName -ErrorAction SilentlyContinue
        if ($g) {
            $remaining += "Cluster group still exists: $($g.Name) [$($g.State)]"
        }
    }
    catch {
    }

    try {
        $resources = @(Get-ClusterResource -ErrorAction SilentlyContinue | Where-Object { $_.OwnerGroup -eq $ClusterGroupName })
        foreach ($r in $resources) {
            $remaining += "Cluster resource still exists: $($r.Name) [$($r.ResourceType) / $($r.State)]"
        }
    }
    catch {
    }

    return @($remaining)
}
