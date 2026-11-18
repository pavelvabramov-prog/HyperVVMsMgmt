# Purpose: Write-ReportField - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Writes report Field for the calling workflow.
function Write-ReportField {
    param([string]$Label, [string]$Value, [string]$ValueColor = 'Gray')
    $prefix = ('{0,-27}: ' -f $Label)
    Write-Host $prefix -NoNewline
    Write-HVMessage -Message $Value -ForegroundColor $ValueColor
}
