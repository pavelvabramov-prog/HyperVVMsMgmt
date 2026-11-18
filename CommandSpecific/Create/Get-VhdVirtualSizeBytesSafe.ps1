# Purpose: Get-VhdVirtualSizeBytesSafe - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Retrieves vhd Virtual Size Bytes Safe for the calling workflow.
function Get-VhdVirtualSizeBytesSafe {
        param([Parameter(Mandatory = $true)][string]$Path)
        $info = Get-VHD -Path $Path -ErrorAction Stop
        return [int64]$info.Size
    }
