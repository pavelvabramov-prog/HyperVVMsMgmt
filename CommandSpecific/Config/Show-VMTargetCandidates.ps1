# Purpose: Show-VMTargetCandidates - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Displays vMTarget Candidates for the calling workflow.
function Show-VMTargetCandidates {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseVMName,

        [Parameter(Mandatory = $true)]
        [object[]]$Candidates
    )

    Write-Host "Candidate Hyper-V VM objects for '$BaseVMName':" -ForegroundColor Yellow

    $index = 1
    foreach ($candidate in @($Candidates)) {
        $state = $null
        try { $state = [string]$candidate.State } catch { $state = $null }
        if ([string]::IsNullOrWhiteSpace($state)) { $state = "Unknown" }

        $id = $null
        try { $id = [string]$candidate.Id } catch { $id = $null }

        if ([string]::IsNullOrWhiteSpace($id)) {
            Write-Host (" [{0}] {1} | State={2}" -f $index, $candidate.Name, $state) -ForegroundColor Yellow
        }
        else {
            Write-Host (" [{0}] {1} | State={2} | Id={3}" -f $index, $candidate.Name, $state, $id) -ForegroundColor Yellow
        }

        $index++
    }
}
