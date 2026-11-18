# Purpose: Write-ExistingADComputerDomainJoinWarning - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Writes existing ADComputer Domain Join Warning for the calling workflow.
function Write-ExistingADComputerDomainJoinWarning {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMName,

        [Parameter(Mandatory = $true)]
        [string]$ComputerName,

        [Parameter(Mandatory = $true)]
        [string]$Domain,

        [switch]$AllowExistingADComputer,

        [switch]$ValidateOnly
    )

    Write-Warning (
        "VM '$VMName': AD computer account '$ComputerName' already exists in domain '$Domain'. " +
        "Be sure that the old VM is offline and the AD computer account was reset or pre-staged."
    )

    if ($AllowExistingADComputer) {
        if ($ValidateOnly) {
            Write-Warning "VM '$VMName': -AllowExistingADComputer specified. Domain join will be allowed during Apply mode."
        }
        else {
            Write-Warning "VM '$VMName': -AllowExistingADComputer specified. Proceeding with domain join using the existing AD computer account."
        }
    }
    else {
        Write-Warning "VM '$VMName': domain join will be skipped. Use -AllowExistingADComputer only for a replacement VM workflow."
    }
}
