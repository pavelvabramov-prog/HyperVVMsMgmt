# Purpose: Test-DomainMatchesLocalHostDomain - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Checks domain Matches Local Host Domain for the calling workflow.
function Test-DomainMatchesLocalHostDomain {
    param([string]$Domain)

    if ([string]::IsNullOrWhiteSpace($Domain)) {
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($env:USERDNSDOMAIN)) {
        return $false
    }

    $left  = $Domain.Trim().Trim('.').ToLower()
    $right = $env:USERDNSDOMAIN.Trim().Trim('.').ToLower()

    return ($left -eq $right)
}
