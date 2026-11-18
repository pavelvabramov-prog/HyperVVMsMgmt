# Purpose: Add-HVClusterVMRole - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Adds hVCluster VMRole for the calling workflow.
function Add-HVClusterVMRole {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$VMName,
        [Parameter(Mandatory)][string]$ClusterName
    )

    # Called locally on the jump host. -VirtualMachine resolves the VM
    # through the specified cluster; do not use Get-VM against the jump host.
    Import-Module FailoverClusters -ErrorAction Stop
    Add-ClusterVirtualMachineRole -Cluster $ClusterName -VirtualMachine $VMName -ErrorAction Stop | Out-Null
}
