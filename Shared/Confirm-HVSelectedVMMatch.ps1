# Purpose: Confirm-HVSelectedVMMatch - shared helper.
# Maintains the existing validation, logging, and execution behavior.

# Checks that the selected VM still matches the expected identity.
function Confirm-HVSelectedVMMatch {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseVMName,

        [Parameter(Mandatory = $true)]
        [string]$CurrentDisplayVMName
    )

    Write-Warning "Selected VM requires confirmation."
    Write-Host "Configured VM Name : $BaseVMName" -ForegroundColor Yellow
    Write-Host "Selected Hyper-V VM: $CurrentDisplayVMName" -ForegroundColor Yellow

    $response = Read-Host "Continue with this VM? Enter Y to proceed, anything else to skip"
    return ($response -eq 'Y' -or $response -eq 'y')
}
