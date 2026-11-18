# Purpose: Show-HVCreateReport - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Displays the validated disk, network, and tag plan for each VM.
function Show-HVCreateReport {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Items)
foreach ($item in $Items) {
    Write-Host ""
    Write-Host "==========$($item.BaseVMName) ($($item.TargetDisplayVMName))==========" -ForegroundColor Cyan
    Write-Host "Disk destination summary for $($item.BaseVMName):"
    foreach ($disk in ($item.DiskDefinitions | Where-Object { $_.IsDefined } | Sort-Object Letter)) {
        if ($disk.Action -eq 'InPlace') {
            Write-Host (" - {0}: {1} -> {2}" -f $disk.Letter, $disk.Action, $disk.InPlace)
        }
        else {
            Write-Host (" - {0}: {1} -> {2}" -f $disk.Letter, $disk.Action, $disk.Layout.DiskPath)
        }
    }

    Write-Host ""
    Write-Host "Network adapter summary:"
    foreach ($net in ($item.NetworkDefinitions | Sort-Object Index)) {
        if ([string]::IsNullOrWhiteSpace($net.SwitchName)) {
            Write-Host (" - {0}: disconnected" -f $net.Name)
        }
        else {
            Write-Host (" - {0}: switch '{1}'" -f $net.Name, $net.SwitchName.Trim())
        }
    }

    # Step 1.5.4: Keep the validated Tags with the disk/network report
    # for this same VM, rather than printing a second batch-wide report.
    Write-Host ""
    Write-Host "Tag validation: PASS" -ForegroundColor Green
    foreach ($category in @('Scope','Env','App','Role','Contact')) {
        $values = @($item.CreateTags | Where-Object { $_ -match ('^{0}:' -f [regex]::Escape($category)) } | ForEach-Object { ($_ -split ':',2)[1] })
        if ($values.Count -gt 0) {
            Write-Host (" - {0}: {1}" -f $category, ($values -join '; '))
        }
    }
}

}
