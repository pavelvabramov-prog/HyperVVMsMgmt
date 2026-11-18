# Purpose: Get-HVCreateNameInventory - shared helper.
# Maintains the existing validation, logging, and execution behavior.

# Retrieves hVCreate Name Inventory for the calling workflow.
function Get-HVCreateNameInventory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TargetHost, [string]$ClusterName)

    $nodes = @($TargetHost)
    if (-not [string]::IsNullOrWhiteSpace($ClusterName)) {
        Import-Module FailoverClusters -ErrorAction Stop
        $nodes = @(Get-ClusterNode -Cluster $ClusterName -ErrorAction Stop | ForEach-Object { $_.Name })
        if ($nodes.Count -eq 0) { throw "Cluster '$ClusterName' returned no nodes. Name validation cannot continue." }
    }
    $inventory = @()
    foreach ($node in $nodes) {
        try {
            $found = @(Invoke-Command -ComputerName $node -ErrorAction Stop -ScriptBlock {
                Import-Module Hyper-V -ErrorAction Stop
                @(Get-VM -ErrorAction Stop | Select-Object Name,Id,ComputerName,Path)
            })
        }
        catch {
            throw "Cannot enumerate VMs on '$node': $($_.Exception.Message). Name validation aborted (fail closed)."
        }
        foreach ($vm in $found) {
            if ($null -eq $vm -or [string]::IsNullOrWhiteSpace([string]$vm.Name)) { continue }
            $inventory += [pscustomobject]@{
                Name = [string]$vm.Name
                Id = [string]$vm.Id
                Host = $node
                Path = [string]$vm.Path
            }
        }
    }
    # Cluster enumeration may return the same VM through multiple nodes.
    @($inventory | Group-Object { if ($_.Id) { $_.Id.ToUpperInvariant() } else { $_.Host + ':' + $_.Name.ToUpperInvariant() } } | ForEach-Object { $_.Group | Select-Object -First 1 })
}
