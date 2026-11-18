# Purpose: Resolve-HVExistingVM - shared helper.
# Maintains the existing validation, logging, and execution behavior.

# Resolves hVExisting VM for the calling workflow.
function Resolve-HVExistingVM {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$VMName,
          [Parameter(Mandatory)][string]$HyperVHost,
          [switch]$ValidateOnly,
          [switch]$ReadOnly,
          $SelectionContext,
          [ValidateSet('Single','Multiple')][string]$PermittedSelection = 'Single',
          [string[]]$InputNames = @())

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
    if ($null -eq $SelectionContext) { $SelectionContext = New-HVSelectionContext }
    $rows = @($hits | ForEach-Object {
        [pscustomobject]@{Id=[string]$_.Id;Name=$_.Name;Node=$_.Node;Kind=$_.Kind;State=$_.State;Original=$_}
    })
    $selection = Resolve-HVBatchSelection -RequestedName $VMName -Candidates $rows `
        -PermittedSelection $PermittedSelection -SelectionContext $SelectionContext `
        -ValidateOnly:$ValidateOnly -ConfirmSelection:(-not $ReadOnly) -InputNames $InputNames
    if ($selection.Status -ne 'Selected') {
        return [pscustomobject]@{Status=$selection.Status;Reason=$selection.Reason;VMName=$VMName}
    }
    foreach ($choice in @($selection.Selected)) {
        $selected = $choice.Original
        $verified = @(Get-VM -ComputerName $selected.Node -ErrorAction Stop | Where-Object { [string]$_.Id -eq [string]$selected.Id })
        if ($verified.Count -ne 1) { throw "Selected VM ID '$($selected.Id)' is no longer present uniquely on '$($selected.Node)'. No tag changes." }
        [pscustomobject]@{
            VM=$verified[0]; ShortName=$VMName; VMName=[string]$verified[0].Name
            VMId=[string]$verified[0].Id; HyperVHost=[string]$selected.Node
            Cluster=$(if($isCluster){$HyperVHost}else{$null}); IsClustered=$isCluster
        }
    }
}
