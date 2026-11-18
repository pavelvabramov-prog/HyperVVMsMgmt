# Purpose: Get-ClusterVMRoleById - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Retrieves cluster VMRole By Id for the calling workflow.
function Get-ClusterVMRoleById {
    param([string]$Cluster,[guid]$Id)
    $hits = @()
    foreach ($r in @(Invoke-HVTiming -Action Measure -TimingLabel 'Cluster resource enumeration' -Target $Cluster -ScriptBlock { Get-ClusterResource -Cluster $Cluster -ErrorAction Stop } | Where-Object { $_.ResourceType -eq 'Virtual Machine' })) {
        $resourceVMId = Get-HVClusterResourceVMId -Resource $r -TimingTarget $Cluster
        if ($resourceVMId -eq $Id.ToString('D')) { $hits += $r }
    }
    if ($hits.Count -gt 1) { throw "Multiple cluster VM resources match VM ID $Id" }
    if ($hits.Count -eq 1) { return [string]$hits[0].OwnerGroup }
    return $null
}
