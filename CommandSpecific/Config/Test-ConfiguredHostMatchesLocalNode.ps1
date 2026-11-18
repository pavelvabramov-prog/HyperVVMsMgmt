# Purpose: Test-ConfiguredHostMatchesLocalNode - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Checks configured Host Matches Local Node for the calling workflow.
function Test-ConfiguredHostMatchesLocalNode {
    param([string]$ConfiguredHost)

    if ([string]::IsNullOrWhiteSpace($ConfiguredHost)) {
        return $false
    }

    $configured = $ConfiguredHost.Trim().Trim('.').ToUpper()
    $localShort = $env:COMPUTERNAME.Trim().Trim('.').ToUpper()
    $localFqdn = if ($env:USERDNSDOMAIN) {
        ("{0}.{1}" -f $env:COMPUTERNAME, $env:USERDNSDOMAIN).Trim().Trim('.').ToUpper()
    }
    else {
        $localShort
    }

    return ($configured -eq $localShort -or $configured -eq $localFqdn -or
        (-not [string]::IsNullOrWhiteSpace($global:HVGC_ExecutionHost) -and $configured -eq $global:HVGC_ExecutionHost.Trim().Trim('.').ToUpper()))
}
