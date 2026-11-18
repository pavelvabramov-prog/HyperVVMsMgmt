# Purpose: Test-HVShortVMName - shared helper.
# Maintains the existing validation, logging, and execution behavior.

# Checks hVShort VMName for the calling workflow.
function Test-HVShortVMName {
    param(
        [Parameter(Mandatory = $true)][string]$BaseVMName,
        [string]$Pattern,
        [string]$Context
    )
    if ([string]::IsNullOrWhiteSpace($BaseVMName)) {
        if ($Context) { throw "$Context VM Name is blank." }
        throw "Short VM name is blank."
    }
    if ([string]::IsNullOrWhiteSpace($Pattern)) { $Pattern = $script:ShortVMNamePattern }
    if ([string]::IsNullOrWhiteSpace($Pattern)) { $Pattern = '^[A-Za-z0-9]{10}$' }
    if ($BaseVMName -notmatch $Pattern) {
        if ($Context -and $Pattern -eq '^[A-Za-z0-9]{10}$') {
            throw "$Context VM Name '$BaseVMName' must be exactly 10 alphanumeric characters."
        }
        throw "Short VM name '$BaseVMName' does not match configured VMNaming.ShortNamePattern: $Pattern"
    }
}
