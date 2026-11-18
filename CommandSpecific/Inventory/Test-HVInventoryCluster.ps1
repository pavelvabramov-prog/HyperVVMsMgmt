# Checks hVInventory Cluster for the calling workflow.
function Test-HVInventoryCluster {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    # Shared cluster discovery is used by Create/Config and Inventory.
    # Its null result means discovery failed; it does not prove the target is a host.
    return ($null -ne (Get-HVClusterPlacement -Name $Name))
}
