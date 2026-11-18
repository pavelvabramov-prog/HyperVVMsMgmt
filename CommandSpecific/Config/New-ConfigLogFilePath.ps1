# Purpose: New-ConfigLogFilePath - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Creates config Log File Path for the calling workflow.
function New-ConfigLogFilePath {
    param([Parameter(Mandatory=$true)][string]$ConfigFilePath)
    Start-HVConfigExecutionLog -ConfigFilePath $ConfigFilePath
}
