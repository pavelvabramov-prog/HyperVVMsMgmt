# Purpose: Test-ComputerNameBasic - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Checks computer Name Basic for the calling workflow.
function Test-ComputerNameBasic {
    param(
        [string]$Name,
        [string]$Context
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw "$Context computer name is blank."
    }

    if ($Name.Length -gt 15) {
        throw "$Context computer name '$Name' exceeds 15 characters."
    }

    if ($Name -match '[\\\/\:\*\?\"<>\|,;=\+\[\]]') {
        throw "$Context computer name '$Name' contains invalid characters."
    }

    if ($Name.StartsWith('-') -or $Name.EndsWith('-')) {
        throw "$Context computer name '$Name' cannot start or end with '-'."
    }
}
