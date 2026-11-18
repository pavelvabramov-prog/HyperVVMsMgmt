# Purpose: Get-VMNamesSafeLocal - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Retrieves vMNames Safe Local for the calling workflow.
function Get-VMNamesSafeLocal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$NamePattern,

        [switch]$Silent
    )

    # Prefer targeted Get-VM calls. On some hosts, plain Get-VM fails when one stale/corrupt
    # VM registration exists, even though targeted Get-VM -Name still works for healthy VMs.
    try {
        return @(Get-VM -Name $NamePattern -ErrorAction Stop | Select-Object -ExpandProperty Name)
    }
    catch {
        $ErrText = $_.Exception.Message

        # For new VM creation, "not found" is expected and means the requested VM name is vacant.
        # Keep real Hyper-V access/service/corruption problems as warnings.
        if ($ErrText -match 'unable to find a virtual machine with name' -or
            $ErrText -match 'cannot find.*virtual machine' -or
            $ErrText -match 'could not find.*virtual machine' -or
            $ErrText -match 'was not found') {

            if (-not $Silent) {
                Write-Host "VM '$NamePattern' name is vacant on local host '$env:COMPUTERNAME'." -ForegroundColor Green
            }
            return @()
        }

        Write-Warning "Targeted VM lookup failed for pattern '$NamePattern' on local host '$env:COMPUTERNAME'. $ErrText"
        return @()
    }
}
