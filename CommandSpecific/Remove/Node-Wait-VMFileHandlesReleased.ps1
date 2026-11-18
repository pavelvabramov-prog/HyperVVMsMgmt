# Purpose: Wait-VMFileHandlesReleased - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Waits for vMFile Handles Released for the calling workflow.
function Wait-VMFileHandlesReleased {
    param([string[]]$Files, [int]$RetryCount=5, [int]$RetryDelaySeconds=2)
    $existing = @($Files | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Sort-Object -Unique)
    if ($existing.Count -eq 0) { return @() }
    $locked = @()
    for ($i=1; $i -le $RetryCount; $i++) {
        $locked = @($existing | Where-Object { Test-FileLocked -Path $_ })
        if ($locked.Count -eq 0) { return @() }
        Write-WarnMsg "Selected files locked. Attempt $i/$RetryCount..."
        foreach ($file in $locked) { Write-WarnMsg " - $file" }
        if ($i -lt $RetryCount) { Start-Sleep -Seconds $RetryDelaySeconds }
    }
    Write-WarnMsg 'Lock-check limit reached; locked files will be preserved.'
    return @($locked)
}
