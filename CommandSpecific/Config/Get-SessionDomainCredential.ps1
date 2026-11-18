# Purpose: Get-SessionDomainCredential - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Retrieves session Domain Credential for the calling workflow.
function Get-SessionDomainCredential {
    $scopesToCheck = @('Script', 'Local', 'Global')

    foreach ($scopeName in $scopesToCheck) {
        $var = Get-Variable -Name 'domainCred' -Scope $scopeName -ErrorAction SilentlyContinue
        if ($null -ne $var -and $var.Value -is [pscredential]) {
            return $var.Value
        }
    }

    return $null
}
