# Purpose: Get-JumpHostADStatus - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Retrieves jump Host ADStatus for the calling workflow.
function Get-JumpHostADStatus {
    param([string]$ComputerName)
    $module = Get-Module -ListAvailable -Name ActiveDirectory
    if (-not $module) {
        return [pscustomobject]@{ Status='Unavailable'; DN=$null; Error='ActiveDirectory module not installed on initiating computer' }
    }
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $obj = Get-ADComputer -Identity $ComputerName -ErrorAction Stop
        return [pscustomobject]@{ Status='Found'; DN=[string]$obj.DistinguishedName; Error=$null }
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        return [pscustomobject]@{ Status='NotFound'; DN=$null; Error=$null }
    }
    catch {
        return [pscustomobject]@{ Status='Error'; DN=$null; Error=$_.Exception.Message }
    }
}
