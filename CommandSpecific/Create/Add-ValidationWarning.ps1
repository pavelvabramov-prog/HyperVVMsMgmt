# Purpose: Add-ValidationWarning - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Adds validation Warning for the calling workflow.
function Add-ValidationWarning {
    param([System.Collections.ArrayList]$List, [string]$Message)
    [void]$List.Add($Message)
}
