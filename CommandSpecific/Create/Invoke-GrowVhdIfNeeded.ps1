# Purpose: Invoke-GrowVhdIfNeeded - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Expands a VHDX only when its current capacity is below the requested target.
function Invoke-GrowVhdIfNeeded {
        param(
            [Parameter(Mandatory = $true)][pscustomobject]$DiskDef,
            [Parameter(Mandatory = $true)][string]$Path
        )

        if ($null -eq $DiskDef.NewSizeIncrToGB) { return }

        $info = Get-VHD -Path $Path -ErrorAction Stop
        $currentBytes = [int64]$info.Size
        $targetBytes = [int64]$DiskDef.NewSizeIncrToGB * 1GB

        if ($targetBytes -gt $currentBytes) {
            Write-Host "Expanding disk $($DiskDef.Letter) from $([math]::Ceiling($currentBytes/1GB)) GB to $($DiskDef.NewSizeIncrToGB) GB: $Path"
            Resize-VHD -Path $Path -SizeBytes $targetBytes | Out-Null
        }
        elseif ($targetBytes -lt $currentBytes) {
            Write-Warning "Disk $($DiskDef.Letter): New Size Incr.to ($($DiskDef.NewSizeIncrToGB) GB) is smaller than current VHDX size ($([math]::Ceiling($currentBytes/1GB)) GB). Shrinking is not supported; value ignored."
        }
    }
