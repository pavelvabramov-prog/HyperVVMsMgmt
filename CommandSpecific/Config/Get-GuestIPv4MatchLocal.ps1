# Purpose: Get-GuestIPv4MatchLocal - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Retrieves guest IPv4 Match Local for the calling workflow.
function Get-GuestIPv4MatchLocal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMName,

        [Parameter(Mandatory = $true)]
        [pscredential]$Credential,

        [Parameter(Mandatory = $true)]
        [string]$IPAddress
    )

    $result = Invoke-Command -VMName $VMName -Credential $Credential -ArgumentList $IPAddress -ScriptBlock {
        param($IPAddress)

        $match = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -eq $IPAddress } |
            Select-Object -First 1

        if ($match) {
            $adapter = Get-NetAdapter -InterfaceIndex $match.InterfaceIndex -ErrorAction SilentlyContinue

            [pscustomobject]@{
                Found          = $true
                InterfaceIndex = $match.InterfaceIndex
                InterfaceAlias = if ($adapter) { $adapter.Name } else { $null }
            }
        }
        else {
            [pscustomobject]@{
                Found          = $false
                InterfaceIndex = $null
                InterfaceAlias = $null
            }
        }
    } -ErrorAction Stop

    return $result
}
