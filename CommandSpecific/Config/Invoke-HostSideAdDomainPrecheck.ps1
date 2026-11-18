# Purpose: Invoke-HostSideAdDomainPrecheck - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Runs host Side Ad Domain Precheck for the calling workflow.
function Invoke-HostSideAdDomainPrecheck {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Domain,

        [Parameter(Mandatory = $true)]
        [pscredential]$DomainCredential,

        [Parameter(Mandatory = $true)]
        [string]$ComputerName,

        [string]$DomainOU
    )

    try {
        $existingComputer = Get-HVConfigADComputer -ComputerName $ComputerName -Domain $Domain -DomainCredential $DomainCredential
    }
    catch {
        $msg = ($_ | Out-String).Trim()

        if (Test-ErrorLooksLikeAuthFailure $msg) {
            throw "DOMAINAUTHFAIL: Authentication to domain '$Domain' failed using supplied credentials."
        }
        elseif (Test-ErrorLooksLikeNameOrConnectivityFailure $msg) {
            return [pscustomobject]@{
                Success         = $false
                Reachable       = $false
                Message         = "DOMAINCHECKFAIL: Domain '$Domain' cannot be reached from this host  -  no Domain Controllers could be contacted."
                ComputerExists  = $null
                OuChecked       = $false
                OuExists        = $null
            }
        }
        else {
            throw "DOMAINCHECKFAIL: $msg"
        }
    }

    $ouChecked = $false
    $ouExists = $null

    if (-not [string]::IsNullOrWhiteSpace($DomainOU)) {
        $ouChecked = $true

        try {
            $ouObject = Get-ADOrganizationalUnit -Identity $DomainOU -Server $Domain -Credential $DomainCredential -ErrorAction Stop
            $ouExists = ($null -ne $ouObject)
        }
        catch {
            $msg = ($_ | Out-String).Trim()

            if (Test-ErrorLooksLikeAuthFailure $msg) {
                throw "DOMAINAUTHFAIL: Authentication to domain '$Domain' failed using supplied credentials."
            }
            elseif (Test-ErrorLooksLikeNameOrConnectivityFailure $msg) {
                return [pscustomobject]@{
                    Success         = $false
                    Reachable       = $false
                    Message         = "DOMAINCHECKFAIL: Domain '$Domain' cannot be reached from this host  -  no Domain Controllers could be contacted."
                    ComputerExists  = $null
                    OuChecked       = $false
                    OuExists        = $null
                }
            }
            else {
                throw "OUCHECKFAIL: $msg"
            }
        }
    }

    return [pscustomobject]@{
        Success         = $true
        Reachable       = $true
        Message         = $null
        ComputerExists  = ($null -ne $existingComputer)
        OuChecked       = $ouChecked
        OuExists        = $ouExists
    }
}
