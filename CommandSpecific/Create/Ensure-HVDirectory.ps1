# Purpose: Ensure-HVDirectory - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Handles hVDirectory for the calling workflow.
function Ensure-HVDirectory {
        param([Parameter(Mandatory = $true)][string]$Path)
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
        }
    }
