# Purpose: Prepare-DiskPath - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Resolves the disk action and destination path before disk preparation.
function Prepare-DiskPath {
        param([Parameter(Mandatory = $true)][pscustomobject]$DiskDef)

        if (-not $DiskDef.IsDefined) { return $null }

        switch ($DiskDef.Action) {
            'InPlace' {
                if (-not (Test-Path -LiteralPath $DiskDef.InPlace)) {
                    throw "Disk $($DiskDef.Letter), InPlace VHDX not found: $($DiskDef.InPlace)"
                }
                Write-Host "Using in-place disk $($DiskDef.Letter): $($DiskDef.InPlace)"
                Invoke-GrowVhdIfNeeded -DiskDef $DiskDef -Path $DiskDef.InPlace
                return $DiskDef.InPlace
            }

            'CopySource' {
                if (-not (Test-Path -LiteralPath $DiskDef.Source)) {
                    throw "Disk $($DiskDef.Letter), Source VHDX not found: $($DiskDef.Source)"
                }
                Ensure-HVDirectory -Path $DiskDef.Layout.DiskRootPath
                if (Test-Path -LiteralPath $DiskDef.Layout.DiskPath) {
                    throw "Disk $($DiskDef.Letter) destination VHDX already exists: $($DiskDef.Layout.DiskPath)"
                }
                Write-Host "Copying disk $($DiskDef.Letter) source to $($DiskDef.Layout.DiskPath)"
                Copy-Item -LiteralPath $DiskDef.Source -Destination $DiskDef.Layout.DiskPath -Force
                Invoke-GrowVhdIfNeeded -DiskDef $DiskDef -Path $DiskDef.Layout.DiskPath
                return $DiskDef.Layout.DiskPath
            }

            'MoveSource' {
                if (-not (Test-Path -LiteralPath $DiskDef.Source)) {
                    throw "Disk $($DiskDef.Letter), Source VHDX not found: $($DiskDef.Source)"
                }
                Ensure-HVDirectory -Path $DiskDef.Layout.DiskRootPath
                if (Test-Path -LiteralPath $DiskDef.Layout.DiskPath) {
                    throw "Disk $($DiskDef.Letter) destination VHDX already exists: $($DiskDef.Layout.DiskPath)"
                }
                Write-Host "MOVING disk $($DiskDef.Letter) source to $($DiskDef.Layout.DiskPath)" -ForegroundColor Yellow
                Move-Item -LiteralPath $DiskDef.Source -Destination $DiskDef.Layout.DiskPath
                Invoke-GrowVhdIfNeeded -DiskDef $DiskDef -Path $DiskDef.Layout.DiskPath
                return $DiskDef.Layout.DiskPath
            }

            'New' {
                if ($null -eq $DiskDef.SizeGB) {
                    throw "Disk $($DiskDef.Letter) Size is missing for new disk creation."
                }
                Ensure-HVDirectory -Path $DiskDef.Layout.DiskRootPath
                if (Test-Path -LiteralPath $DiskDef.Layout.DiskPath) {
                    throw "Disk $($DiskDef.Letter) destination VHDX already exists: $($DiskDef.Layout.DiskPath)"
                }

                $sizeBytes = [int64]$DiskDef.SizeGB * 1GB
                if ($DiskDef.IsFixed -eq $true) {
                    Write-Host "Creating fixed disk $($DiskDef.Letter) ($($DiskDef.SizeGB) GB): $($DiskDef.Layout.DiskPath)"
                    New-VHD -Path $DiskDef.Layout.DiskPath -SizeBytes $sizeBytes -Fixed | Out-Null
                }
                else {
                    Write-Host "Creating dynamic disk $($DiskDef.Letter) ($($DiskDef.SizeGB) GB): $($DiskDef.Layout.DiskPath)"
                    New-VHD -Path $DiskDef.Layout.DiskPath -SizeBytes $sizeBytes -Dynamic | Out-Null
                }
                return $DiskDef.Layout.DiskPath
            }
        }

        throw "Unknown disk action '$($DiskDef.Action)' for disk $($DiskDef.Letter)."
    }
