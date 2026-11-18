# Purpose: Resolve-HVExistingVM - shared helper.
# Maintains the existing validation, logging, and execution behavior.

# Resolves hVExisting VM for the calling workflow.
function Resolve-HVExistingVM {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$VMName,
          [Parameter(Mandatory)][string]$HyperVHost,
          [switch]$ValidateOnly,
          [switch]$ReadOnly)

    # Reuse the same classifier and interactive selection/confirmation functions
    # as hv-config. Never return the first host-local candidate.
    $clusterNodes = @()
    $isCluster = $false
    try {
        $clusterNodes = @(Invoke-Command -ComputerName $HyperVHost -ScriptBlock {
            Import-Module FailoverClusters -ErrorAction Stop
            @(Get-ClusterNode | Select-Object -ExpandProperty Name)
        } -ErrorAction Stop)
        $isCluster = ($clusterNodes.Count -gt 0)
    } catch { $clusterNodes = @() }
    $nodes = if ($isCluster) { @($clusterNodes) } else { @($HyperVHost) }
    $hits = @()
    foreach ($node in $nodes) {
        # A failed node query must not silently produce a partial cluster inventory.
        $vms = @(Get-VM -ComputerName $node -ErrorAction Stop)
        foreach ($vm in $vms) {
            $kind = Get-HVVMNameClassification -ShortVMName $VMName -ExistingVMName ([string]$vm.Name)
            if ($null -eq $kind) { continue }
            $hits += [pscustomobject]@{
                Node=[string]$node; Name=[string]$vm.Name; Id=[string]$vm.Id
                State=$vm.State; Kind=$kind; VM=$vm
            }
        }
    }
    $hits = @($hits | Sort-Object Id -Unique)
    if ($hits.Count -eq 0) { throw "NoAnyMatches: VM '$VMName' was not found on '$HyperVHost'." }
    if ($hits.Count -gt 1) {
        Write-Host "Candidate Hyper-V VM objects for '$VMName' across target nodes:" -ForegroundColor Yellow
        $number = 0
        foreach ($hit in $hits) {
            $number++
            Write-Host (" [{0}] {1} | Host={2} | Match={3} | State={4} | Id={5}" -f $number,$hit.Name,$hit.Node,$hit.Kind,$hit.State,$hit.Id) -ForegroundColor Yellow
        }
        # Same cluster-dispatcher behavior as hv-config, including ValidateOnly.
        $selected = Select-VMTargetCandidate -BaseVMName $VMName -Candidates $hits
        if (-not $selected) {
            Write-Host "Selection skipped for '$VMName'; no tag changes."
            return [pscustomobject]@{ Status='Skipped'; Reason='Selection cancelled'; VMName=$VMName }
        }
        # Read-only and dry-run operations still require explicit candidate selection,
        # but do not need a second authorization prompt.
        if (-not ($ValidateOnly -or $ReadOnly)) {
            $approved = Confirm-HVSelectedVMMatch -BaseVMName $VMName -CurrentDisplayVMName ("{0} on {1} (VM ID {2})" -f $selected.Name,$selected.Node,$selected.Id)
            if (-not $approved) {
                Write-Host "Selection skipped for '$VMName'; no tag changes."
                return [pscustomobject]@{ Status='Skipped'; Reason='Confirmation declined'; VMName=$VMName }
            }
        }
    } else { $selected = $hits[0] }

    # Identity check protects against a stale/moved/replaced VM after selection.
    $verified = @(Get-VM -ComputerName $selected.Node -ErrorAction Stop | Where-Object { [string]$_.Id -eq [string]$selected.Id })
    if ($verified.Count -ne 1) { throw "Selected VM ID '$($selected.Id)' is no longer present uniquely on '$($selected.Node)'. No tag changes." }
    [pscustomobject]@{
        VM=$verified[0]; ShortName=$VMName; VMName=[string]$verified[0].Name
        VMId=[string]$verified[0].Id; HyperVHost=[string]$selected.Node
        Cluster=$(if($isCluster){$HyperVHost}else{$null}); IsClustered=$isCluster
    }
}
