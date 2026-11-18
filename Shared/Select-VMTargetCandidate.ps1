# Purpose: Select-VMTargetCandidate - shared helper.
# Maintains the existing validation, logging, and execution behavior.

# Selects vMTarget Candidate for the calling workflow.
function Select-VMTargetCandidate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseVMName,

        [Parameter(Mandatory = $true)]
        [object[]]$Candidates
    )

    $candidateList = @($Candidates)
    if ($candidateList.Count -lt 1) {
        throw "No candidates are available for '$BaseVMName'."
    }

    # Candidate list is printed by the caller before this function is called.
    # Keep this function responsible only for reading/validating the user selection,
    # so Apply mode does not display the same candidates twice.

    while ($true) {
        $answer = Read-Host ("Select VM for '{0}' by number [1-{1}], or Q to skip" -f $BaseVMName, $candidateList.Count)

        if ($answer -match '^[Qq]$') {
            return $null
        }

        $selectedIndex = 0
        if ([int]::TryParse($answer, [ref]$selectedIndex)) {
            if ($selectedIndex -ge 1 -and $selectedIndex -le $candidateList.Count) {
                return $candidateList[$selectedIndex - 1]
            }
        }

        Write-Warning "Invalid selection '$answer'. Enter a number from 1 to $($candidateList.Count), or Q to skip."
    }
}
