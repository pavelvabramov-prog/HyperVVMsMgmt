# Purpose: Get-ComputerNameFromVMDisplayName - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Retrieves computer Name From VMDisplay Name for the calling workflow.
function Get-ComputerNameFromVMDisplayName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DisplayName,

        [string]$OriginalInputName
    )

    # Extract the real AD computer name from VM display names such as:
    #   HVTSTWS016
    #   HVTSTWS016 - Description
    #   Non-Functional - HVTSTWS016 - VM 2012R2 FoIP
    #   DECOM - HVTSTWS004 - CRM App 1
    #
    # We prefer a 10-character alphanumeric token because this matches the VM/computer
    # naming convention used by the Hyper-V script family.

    $candidateSources = @()

    if (-not [string]::IsNullOrWhiteSpace($OriginalInputName)) {
        $candidateSources += $OriginalInputName
    }

    if (-not [string]::IsNullOrWhiteSpace($DisplayName)) {
        $candidateSources += $DisplayName
    }

    foreach ($source in $candidateSources) {
        $matches = [regex]::Matches($source, '(?i)(^|[^A-Za-z0-9])([A-Za-z0-9]{10})($|[^A-Za-z0-9])')

        if ($matches.Count -eq 1) {
            return $matches[0].Groups[2].Value.ToUpper()
        }

        if ($matches.Count -gt 1) {
            $tokens = @($matches | ForEach-Object { $_.Groups[2].Value.ToUpper() } | Sort-Object -Unique)
            if ($tokens.Count -eq 1) {
                return $tokens[0]
            }
            throw "Unable to determine AD computer name from '$source'. Multiple 10-character tokens found: $($tokens -join ', ')"
        }
    }

    # Fallback for uncommon names that do not follow the 10-character convention.
    # This keeps compatibility with older/manual VMs, but avoids using prefixes like
    # 'Non-Functional' when a valid 10-character token exists elsewhere.
    $token = ($DisplayName -split '\s+')[0].Trim()

    if ([string]::IsNullOrWhiteSpace($token)) {
        return $DisplayName.Trim()
    }

    return $token
}
