# Purpose: Invoke-HVTagSingle - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Runs hVTag Single for the calling workflow.
function Invoke-HVTagSingle {
    param([string]$ComputerName,[string]$Type,[string]$HyperVHost,[string]$UserName,[string]$Action,[string[]]$Tags,[switch]$ValidateOnly)
    if ($Type -eq 'HyperV' -and -not $HyperVHost) { throw 'HyperV requires -HyperVHost or a TargetHost in the CSV.' }
    if ($Type -eq 'PhysicalLinux' -and -not $UserName) { throw 'PhysicalLinux requires -UserName.' }
    if ($Type -ne 'PhysicalLinux' -and $UserName) { throw '-UserName is only valid for PhysicalLinux targets.' }
    switch ($Type) {
        'HyperV' { Invoke-HyperVTagOperation -VMName $ComputerName -HyperVHost $HyperVHost -Action $Action -RequestedTags $Tags -ValidateOnly:$ValidateOnly }
        'PhysicalWindows' { Invoke-PhysicalWindowsTagOperation -ComputerName $ComputerName -Action $Action -RequestedTags $Tags -ValidateOnly:$ValidateOnly }
        'PhysicalLinux' { Invoke-PhysicalLinuxTagOperation -ComputerName $ComputerName -UserName $UserName -Action $Action -RequestedTags $Tags -ValidateOnly:$ValidateOnly }
    }
}
