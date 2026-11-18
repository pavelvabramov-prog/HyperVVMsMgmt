# Single-candidate policy adapter; candidate discovery/classification is shared by callers.
function Select-VMTargetCandidate {
    param([Parameter(Mandatory)][string]$BaseVMName,[Parameter(Mandatory)][object[]]$Candidates)
    $context = New-HVSelectionContext
    $rows = @($Candidates | ForEach-Object {
        [pscustomobject]@{Id=[string]$_.Id;Name=[string]$_.Name;Node=[string]$_.Node;Kind=[string]$_.Kind;State=$_.State;Original=$_}
    })
    # Caller already displays candidates; shared engine can suppress its duplicate list.
    $result = Resolve-HVBatchSelection -RequestedName $BaseVMName -Candidates $rows `
        -PermittedSelection Single -SelectionContext $context -SuppressCandidateDisplay
    if ($result.Status -ne 'Selected') { return $null }
    return $result.Selected[0].Original
}
