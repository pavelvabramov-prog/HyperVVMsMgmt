# Purpose: Get-NormalizedDomainPrincipalNames - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Retrieves normalized Domain Principal Names for the calling workflow.
function Get-NormalizedDomainPrincipalNames {
    param(
        [string[]]$Users,
        [string]$Domain
    )

    $result = New-Object System.Collections.ArrayList

    foreach ($user in @($Users)) {
        if ([string]::IsNullOrWhiteSpace($user)) {
            continue
        }

        $trimmed = $user.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            continue
        }

        $normalized = $trimmed
        if ($normalized -notmatch '\\' -and $normalized -notmatch '@') {
            if ([string]::IsNullOrWhiteSpace($Domain)) {
                throw "Cannot normalize AD user '$trimmed' because config field 'Domain' is blank. Use DOMAIN\user or user@domain format, or specify 'Domain'."
            }

            $normalized = "$Domain\$normalized"
        }

        if (-not ($result -contains $normalized)) {
            [void]$result.Add($normalized)
        }
    }

    return @($result)
}
