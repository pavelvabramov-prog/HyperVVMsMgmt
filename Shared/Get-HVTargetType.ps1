# Purpose: Get-HVTargetType - shared helper.
# Maintains the existing validation, logging, and execution behavior.

# Retrieves hVTarget Type for the calling workflow.
function Get-HVTargetType {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name,[object[]]$Items)
    Get-HVClusterPlacement -Name $Name -Items $Items
}

# Config compatibility: probe locally, then retain its host fallback on any failure.
function Get-HVConfigTargetType {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Name)
    try {
        return Get-HVClusterProbe -Name $Name
    } catch {
        return [pscustomobject]@{ ClusterName = $null; Nodes = @($Name) }
    }
}
