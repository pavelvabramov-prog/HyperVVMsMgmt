# Purpose: Test-LocalHostName - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

function Test-LocalHostName([string]$Name) {
    $names = @($env:COMPUTERNAME, "$env:COMPUTERNAME.$env:USERDNSDOMAIN", 'localhost', '.', '127.0.0.1')
    return ($Name -in $names)
}
