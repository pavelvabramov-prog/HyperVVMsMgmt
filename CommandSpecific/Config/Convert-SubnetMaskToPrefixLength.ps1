# Purpose: Convert-SubnetMaskToPrefixLength - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Converts subnet Mask To Prefix Length for the calling workflow.
function Convert-SubnetMaskToPrefixLength {
    param([string]$Mask)

    $octets = $Mask.Split('.')
    if ($octets.Count -ne 4) {
        throw "Invalid subnet mask '$Mask'"
    }

    $binary = foreach ($o in $octets) {
        if ($o -notmatch '^\d+$') {
            throw "Invalid subnet mask '$Mask'"
        }

        $n = [int]$o
        if ($n -lt 0 -or $n -gt 255) {
            throw "Invalid subnet mask '$Mask'"
        }

        [Convert]::ToString($n, 2).PadLeft(8, '0')
    }

    $bits = ($binary -join "")
    if ($bits -notmatch '^1*0*$') {
        throw "Invalid non-contiguous subnet mask '$Mask'"
    }

    return ($bits.ToCharArray() | Where-Object { $_ -eq '1' }).Count
}
