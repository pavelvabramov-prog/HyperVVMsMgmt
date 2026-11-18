# Purpose: Get-HVClusterProbe - shared helper.
# Maintains the existing validation, logging, and execution behavior.

# Canonical, self-contained cluster probe. Safe for local and remote execution.
# Consumers choose their own fallback/error behavior on failure.
function Get-HVClusterProbe {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    Import-Module FailoverClusters -ErrorAction Stop
    $cluster = Get-Cluster -Name $Name -ErrorAction Stop
    $nodes = @(Get-ClusterNode -Cluster $cluster.Name -ErrorAction Stop |
        Where-Object State -eq 'Up' | ForEach-Object { $_.Name })
    if (-not $nodes.Count) { throw "No online nodes in cluster $($cluster.Name)" }
    [pscustomobject]@{ ClusterName = $cluster.Name; Nodes = @($nodes) }
}
