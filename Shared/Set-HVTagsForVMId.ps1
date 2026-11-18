# Purpose: Set-HVTagsForVMId - shared helper.
# Maintains the existing validation, logging, and execution behavior.

# Assigns Tags to the exact VM identified by GUID, then verifies the Notes update.
function Set-HVTagsForVMId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$VMId,
        [Parameter(Mandatory)][string]$ExpectedName,
        [Parameter(Mandatory)][string]$HyperVHost,
        [Parameter(Mandatory)][AllowEmptyString()][string]$NewNotes
    )
    # Always resolve by immutable VM ID and confirm display name before writing.
    Invoke-Command -ComputerName $HyperVHost -ErrorAction Stop -ScriptBlock {
        param([string]$SelectedVMId, [string]$Name, [string]$NotesToWrite)
        $ErrorActionPreference = 'Stop'
        $target = Get-VM -Id ([guid]$SelectedVMId) -ErrorAction Stop
        if ([string]$target.Name -cne $Name) {
            throw "VM identity changed before tagging: expected '$Name', found '$($target.Name)'."
        }
        Set-VM -VM $target -Notes $NotesToWrite -ErrorAction Stop
        $saved = Get-VM -Id ([guid]$SelectedVMId) -ErrorAction Stop
        if ([string]$saved.Notes -cne $NotesToWrite) {
            throw "Tag write verification failed for VM ID '$SelectedVMId'."
        }
    } -ArgumentList $VMId,$ExpectedName,$NewNotes | Out-Null
}
