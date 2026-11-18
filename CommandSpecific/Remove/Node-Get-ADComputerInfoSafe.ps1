# Purpose: Get-ADComputerInfoSafe - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Retrieves aDComputer Info Safe for the calling workflow.
function Get-ADComputerInfoSafe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ComputerName
    )

    $result = [ordered]@{
        ADModuleAvailable = $false
        Found             = $false
        Computer          = $null
        Error             = $null
    }

    $adModule = Get-Module -ListAvailable -Name ActiveDirectory
    if (-not $adModule) {
        return [pscustomobject]$result
    }

    $result.ADModuleAvailable = $true

    try {
        Import-Module ActiveDirectory -ErrorAction Stop | Out-Null

        $adObj = Get-ADComputer -Identity $ComputerName -Properties DistinguishedName -ErrorAction Stop
        if ($adObj) {
            $result.Found    = $true
            $result.Computer = $adObj
        }
    }
    catch {
        $result.Error = $_.Exception.Message
    }

    return [pscustomobject]$result
}
