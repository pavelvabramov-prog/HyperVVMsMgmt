# Purpose: Resolve-VMTargetLocal - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Resolves vMTarget Local for the calling workflow.
function Resolve-VMTargetLocal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseVMName,
        [string]$ExpectedVMId
    )

    Import-Module Hyper-V -ErrorAction Stop

    $localHost = $env:COMPUTERNAME
    $localVMs = @(Get-VM -ErrorAction Stop)

    # Creates vMResolution Result for the calling workflow.
    function New-VMResolutionResult {
        param(
            [string]$MatchType,
            [bool]$RequiresConfirmation,
            [AllowNull()][string]$CurrentDisplayVMName,
            [object[]]$Candidates = @()
        )

        [pscustomobject]@{
            MatchType            = $MatchType
            RequiresConfirmation = $RequiresConfirmation
            CurrentDisplayVMName = $CurrentDisplayVMName
            ResolvedHyperVHost   = $localHost
            Candidates           = @($Candidates)
        }
    }

    # Dispatcher has already selected and confirmed a cluster-wide candidate.
    # Verify its immutable ID on the execution node; never reselect by name.
    if (-not [string]::IsNullOrWhiteSpace($ExpectedVMId)) {
        $selected = @($localVMs | Where-Object { [string]$_.Id -eq $ExpectedVMId })
        if ($selected.Count -ne 1) { throw "Selected VM ID '$ExpectedVMId' was not found uniquely on '$localHost'. Aborting." }
        $kind = Get-HVVMNameClassification -ShortVMName $BaseVMName -ExistingVMName ([string]$selected[0].Name)
        if ($null -eq $kind) { throw "Selected VM ID '$ExpectedVMId' no longer matches '$BaseVMName'. Aborting." }
        return (New-VMResolutionResult -MatchType ("$kind/ClusterSelected") -RequiresConfirmation $false -CurrentDisplayVMName $selected[0].Name -Candidates @($selected[0]))
    }

    # Shared pure matcher; Config keeps the original host-resolution result shape.
    $match = Find-HVVMMatches -ShortVMName $BaseVMName -VMs $localVMs
    return (New-VMResolutionResult -MatchType $match.MatchType -RequiresConfirmation $match.RequiresConfirmation -CurrentDisplayVMName $match.CurrentDisplayVMName -Candidates @($match.Candidates))
}
