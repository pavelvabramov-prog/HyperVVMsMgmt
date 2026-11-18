# Purpose: Invoke-GuestSideTargetDomainPrecheck - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Runs guest Side Target Domain Precheck for the calling workflow.
function Invoke-GuestSideTargetDomainPrecheck {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMName,

        [Parameter(Mandatory = $true)]
        [pscredential]$Credential,

        [Parameter(Mandatory = $true)]
        [string]$Domain,

        [Parameter(Mandatory = $true)]
        [pscredential]$DomainCredential,

        [Parameter(Mandatory = $true)]
        [string]$ComputerName,

        [string]$DomainOU
    )

    $bindUser = $DomainCredential.UserName
    $bindPass = $DomainCredential.GetNetworkCredential().Password

    return Invoke-PsDirectWithRetry `
        -VMName $VMName `
        -Credential $Credential `
        -ArgumentList @($Domain, $bindUser, $bindPass, $ComputerName, $DomainOU) `
        -Attempts 6 `
        -DelaySeconds 10 `
        -StepName "Guest-side target-domain precheck" `
        -ScriptBlock {
            param($Domain, $BindUser, $BindPass, $ComputerName, $DomainOU)

            # Checks local Auth Failure for the calling workflow.
            function Test-LocalAuthFailure {
                param([string]$Message)

                if ([string]::IsNullOrWhiteSpace($Message)) { return $false }

                return (
                    $Message -match 'Access is denied' -or
                    $Message -match 'Logon failure' -or
                    $Message -match 'The user name or password is incorrect' -or
                    $Message -match 'unknown user name or bad password' -or
                    $Message -match 'AccessDenied'
                )
            }

            # Handles ldap Filter Value for the calling workflow.
            function Escape-LdapFilterValue {
                param([string]$Value)

                if ($null -eq $Value) { return '' }

                return ($Value `
                    -replace '\\', '\5c' `
                    -replace '\*', '\2a' `
                    -replace '\(', '\28' `
                    -replace '\)', '\29' `
                    -replace "`0", '\00')
            }

            try {
                $rootDse = New-Object System.DirectoryServices.DirectoryEntry(
                    "LDAP://$Domain/RootDSE",
                    $BindUser,
                    $BindPass
                )
                $null = $rootDse.RefreshCache()
                $defaultNamingContext = [string]$rootDse.Properties['defaultNamingContext'][0]

                if ([string]::IsNullOrWhiteSpace($defaultNamingContext)) {
                    throw "defaultNamingContext was not returned by RootDSE."
                }
            }
            catch {
                $msg = $_.Exception.Message

                if (Test-LocalAuthFailure $msg) {
                    throw "DOMAINAUTHFAIL: $msg"
                }
                else {
                    throw "DOMAINCONNECTFAIL: $msg"
                }
            }

            try {
                $searchRoot = New-Object System.DirectoryServices.DirectoryEntry(
                    "LDAP://$Domain/$defaultNamingContext",
                    $BindUser,
                    $BindPass
                )

                $searcher = New-Object System.DirectoryServices.DirectorySearcher($searchRoot)
                $escapedComputerName = Escape-LdapFilterValue $ComputerName
                $searcher.PageSize = 1000
                $searcher.Filter = "(&(objectCategory=computer)(|(cn=$escapedComputerName)(name=$escapedComputerName)(sAMAccountName=$escapedComputerName`$)))"
                $result = $searcher.FindOne()
                $computerExists = ($null -ne $result)
            }
            catch {
                $msg = $_.Exception.Message

                if (Test-LocalAuthFailure $msg) {
                    throw "DOMAINAUTHFAIL: $msg"
                }
                else {
                    throw "DOMAINCONNECTFAIL: $msg"
                }
            }

            $ouChecked = $false
            $ouExists = $null

            if (-not [string]::IsNullOrWhiteSpace($DomainOU)) {
                $ouChecked = $true

                try {
                    $ouEntry = New-Object System.DirectoryServices.DirectoryEntry(
                        "LDAP://$Domain/$DomainOU",
                        $BindUser,
                        $BindPass
                    )
                    $null = $ouEntry.NativeGuid
                    $ouExists = $true
                }
                catch {
                    $msg = $_.Exception.Message

                    if ($msg -match 'There is no such object on the server' -or $msg -match 'cannot find the object' -or $msg -match 'Directory object not found') {
                        $ouExists = $false
                    }
                    elseif (Test-LocalAuthFailure $msg) {
                        throw "DOMAINAUTHFAIL: $msg"
                    }
                    else {
                        throw "DOMAINCONNECTFAIL: $msg"
                    }
                }
            }

            [pscustomobject]@{
                Success         = $true
                ComputerExists  = $computerExists
                OuChecked       = $ouChecked
                OuExists        = $ouExists
            }
        }
}
