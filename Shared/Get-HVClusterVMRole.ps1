# Purpose: Get-HVClusterVMRole - shared helper.
# Maintains the existing validation, logging, and execution behavior.

# Retrieves hVCluster VMRole for the calling workflow.
function Get-HVClusterVMRole {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$VMName,[string]$ClusterName)
    Import-Module FailoverClusters -ErrorAction Stop
    $groups = if ($ClusterName) { Get-ClusterGroup -Cluster $ClusterName -ErrorAction Stop } else { Get-ClusterGroup -ErrorAction Stop }
    $groups | Where-Object { $_.GroupType -eq 'VirtualMachine' -and $_.Name -eq $VMName }
}
