# Purpose: Get-HVClusterPlacement - shared helper.
# Maintains the existing validation, logging, and execution behavior.

# Retrieves hVCluster Placement for the calling workflow.
function Get-HVClusterPlacement {
    [CmdletBinding()]
    param([string]$Name, [object[]]$Items)
    # Get the canonical probe definition, which is self-contained and remoting-safe.
    $probe = (Get-Command Get-HVClusterProbe -CommandType Function -ErrorAction Stop).ScriptBlock
    try {
        if (Test-LocalHostName $Name) { return (& $probe -Name $Name) }
        return Invoke-Command -ComputerName $Name -ScriptBlock $probe -ArgumentList $Name -ErrorAction Stop
    } catch {
        # Preserve Create/Inventory's historical null-on-failed-discovery contract.
        return $null
    }
}
