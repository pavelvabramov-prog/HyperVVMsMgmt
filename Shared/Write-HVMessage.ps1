# Purpose: Write-HVMessage - shared helper.
# Maintains the existing validation, logging, and execution behavior.

# Writes hVMessage for the calling workflow.
function Write-HVMessage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Message,[ConsoleColor]$ForegroundColor = [ConsoleColor]::Gray)
    Write-Host $Message -ForegroundColor $ForegroundColor
}
