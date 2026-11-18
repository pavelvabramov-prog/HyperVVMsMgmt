# Purpose: Test-IsElevated - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Checks is Elevated for the calling workflow.
function Test-IsElevated {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
