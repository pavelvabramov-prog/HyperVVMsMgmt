# Purpose: Test-ErrorLooksLikeNameOrConnectivityFailure - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Checks error Looks Like Name Or Connectivity Failure for the calling workflow.
function Test-ErrorLooksLikeNameOrConnectivityFailure {
    param([string]$Message)

    if ([string]::IsNullOrWhiteSpace($Message)) { return $false }

    return (
        $Message -match 'cannot find the path' -or
        $Message -match 'network path was not found' -or
        $Message -match 'RPC server is unavailable' -or
        $Message -match 'domain either does not exist or could not be contacted' -or
        $Message -match 'No such host is known' -or
        $Message -match 'The network name cannot be found' -or
        $Message -match 'The server is not operational' -or
        $Message -match 'Unable to contact the server'
    )
}
