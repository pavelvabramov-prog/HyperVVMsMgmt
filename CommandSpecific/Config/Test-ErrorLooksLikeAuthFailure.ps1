# Purpose: Test-ErrorLooksLikeAuthFailure - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Checks error Looks Like Auth Failure for the calling workflow.
function Test-ErrorLooksLikeAuthFailure {
    param([string]$Message)

    if ([string]::IsNullOrWhiteSpace($Message)) { return $false }

    return (
        $Message -match 'Access is denied' -or
        $Message -match 'Logon failure' -or
        $Message -match 'The user name or password is incorrect' -or
        $Message -match 'unknown user name or bad password' -or
        $Message -match 'AccessDenied'
    )
}
