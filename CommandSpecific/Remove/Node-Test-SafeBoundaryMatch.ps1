# Purpose: Test-SafeBoundaryMatch - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Checks safe Boundary Match for the calling workflow.
function Test-SafeBoundaryMatch {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseName,

        [Parameter(Mandatory = $true)]
        [string]$CandidateName
    )

    if ([string]::IsNullOrWhiteSpace($BaseName) -or [string]::IsNullOrWhiteSpace($CandidateName)) {
        return $false
    }

    $escaped = [regex]::Escape($BaseName)

    # Safe boundary:
    # - exact match
    # - or characters before/after base token are NOT alphanumeric
    #
    # Matches:
    #   HVTSTVM001
    #   HVTSTVM001_old
    #   HVTSTVM001 - Description
    #   Legacy - HVTSTVM001 - Description
    #
    # Does NOT match:
    #   HVTSTVM0018
    #   XHVTSTVM001Y
    $pattern = "(?i)(^|[^A-Za-z0-9])$escaped($|[^A-Za-z0-9])"

    return [regex]::IsMatch($CandidateName, $pattern)
}
