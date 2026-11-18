# Purpose: Test-IPLooksVacant - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Checks iPLooks Vacant for the calling workflow.
function Test-IPLooksVacant {
    param([string]$IPAddress)

    if ([string]::IsNullOrWhiteSpace($IPAddress)) {
        return $true
    }

    try {
        $reply = Test-Connection -ComputerName $IPAddress -Count 1 -Quiet -ErrorAction SilentlyContinue
        return (-not $reply)
    }
    catch {
        return $true
    }
}
