# Sort only the candidate presentation order; do not change discovery or selection policy.
function Sort-HVSelectionCandidates {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Candidates,
          [string[]]$InputNames = @(),
          [string]$RequestedName = '')
    $positions = @{}
    for ($i = 0; $i -lt $InputNames.Count; $i++) {
        $name = ([string]$InputNames[$i]).Trim()
        if ($name -and -not $positions.ContainsKey($name)) { $positions[$name] = $i }
    }
    @($Candidates | Sort-Object -Property @(
        @{Expression={ if ($positions.ContainsKey([string]$_.Name)) { 0 } else { 1 } }},
        @{Expression={ if ($positions.ContainsKey([string]$_.Name)) { $positions[[string]$_.Name] } else { [int]::MaxValue } }},
        @{Expression={ if ([string]$_.Name -ieq [string]$RequestedName) { 0 } else { 1 } }},
        @{Expression={ switch -Regex ([string]$_.Kind) { '^Exact' {0;break} '^Safe' {1;break} '^Questionable' {2;break} default {3} } }},
        @{Expression={ [string]$_.Name }},
        @{Expression={ [string]$_.Node }},
        @{Expression={ [string]$_.Id }}
    ))
}
