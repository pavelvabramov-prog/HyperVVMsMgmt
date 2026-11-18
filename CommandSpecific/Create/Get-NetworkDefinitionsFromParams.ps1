# Purpose: Get-NetworkDefinitionsFromParams - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Retrieves network Definitions From Params for the calling workflow.
function Get-NetworkDefinitionsFromParams {
    param([Parameter(Mandatory = $true)][hashtable]$ParamBlock)

    $numbers = New-Object System.Collections.Generic.List[int]
    foreach ($key in $ParamBlock.Keys) {
        if ($key -match '^Network_(\d+)$') {
            [void]$numbers.Add([int]$matches[1])
        }
    }

    if ($numbers.Count -eq 0) {
        $numbers.Add(1) | Out-Null
    }

    $numbers = $numbers | Sort-Object -Unique

    $items = foreach ($n in $numbers) {
        [pscustomobject]@{
            Index      = $n
            Name       = "Network Adapter $n"
            SwitchName = if ($ParamBlock.ContainsKey("Network_$n")) { $ParamBlock["Network_$n"] } else { $null }
            VlanId     = if ($ParamBlock.ContainsKey("VLAN_$n")) { Get-OptionalInt -Value $ParamBlock["VLAN_$n"] } else { $null }
        }
    }

    ,$items
}
