# Purpose: Get-HVADComputer - shared helper.
# Maintains the existing validation, logging, and execution behavior.

# Retrieves hVADComputer for the calling workflow.
function Get-HVADComputer {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ComputerName)
    Import-Module ActiveDirectory -ErrorAction Stop
    Get-ADComputer -Identity $ComputerName -ErrorAction SilentlyContinue
}


# Config compatibility implementation; canonical Create API above is preserved.
function Get-HVConfigADComputer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ComputerName,
        [Parameter(Mandatory=$true)][string]$Domain,
        [Parameter(Mandatory=$true)][pscredential]$DomainCredential
    )
    $escapedComputerName = $ComputerName.Replace("'", "''")
    Get-ADComputer -Filter "Name -eq '$escapedComputerName'" -Server $Domain -Credential $DomainCredential -ErrorAction Stop
}

# Resolve the configured Hyper-V host or cluster for Config dispatch.
