# Purpose: Add-ValidationError - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Adds validation Error for the calling workflow.
function Add-ValidationError {
    param([System.Collections.ArrayList]$List, [string]$Message)
    [void]$List.Add($Message)
}
