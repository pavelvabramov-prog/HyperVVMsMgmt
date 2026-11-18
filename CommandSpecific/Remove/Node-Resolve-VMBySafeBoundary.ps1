# Purpose: Resolve-VMBySafeBoundary - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Resolves vMBy Safe Boundary for the calling workflow.
function Resolve-VMBySafeBoundary {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseName
    )

    $allVMs = Get-VM -ErrorAction Stop
    $matches = @($allVMs | Where-Object { Test-SafeBoundaryMatch -BaseName $BaseName -CandidateName $_.Name })

    if (-not $matches -or $matches.Count -eq 0) {
        throw "No local VM matched '$BaseName' using SafeBoundary logic."
    }

    if ($matches.Count -gt 1) {
        $names = $matches | Select-Object -ExpandProperty Name
        throw "More than one local VM matched '$BaseName' using SafeBoundary logic: $($names -join ', ')"
    }

    return $matches[0]
}
