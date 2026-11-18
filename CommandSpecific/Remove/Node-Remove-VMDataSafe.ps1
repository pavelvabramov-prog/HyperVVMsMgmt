# Purpose: Remove-VMDataSafe - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Removes vMData Safe for the calling workflow.
function Remove-VMDataSafe {
    param(
        [string[]]$DirectDisks,
        [string[]]$SidecarFiles,
        [string[]]$VMConfigRuntimeFiles,
        [string[]]$FolderScanCandidates,
        [string[]]$Folders,
        [string]$VMShortName,
        [switch]$DeleteFolderScanCandidates
    )

    $removedDirectDisks          = New-Object 'System.Collections.Generic.List[string]'
    $removedSidecarFiles         = New-Object 'System.Collections.Generic.List[string]'
    $removedVMConfigRuntimeFiles = New-Object 'System.Collections.Generic.List[string]'
    $removedFolderCandidates     = New-Object 'System.Collections.Generic.List[string]'
    $removedFolders              = New-Object 'System.Collections.Generic.List[string]'
    $failedItems                 = New-Object 'System.Collections.Generic.List[string]'

    # Removes file Group for the calling workflow.
    function Remove-FileGroup {
        param(
            [string[]]$Files,
            [System.Collections.Generic.List[string]]$RemovedList,
            [string]$Label
        )

        foreach ($file in ($Files | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)) {
            try {
                if (Test-Path -LiteralPath $file) {
                    Remove-Item -LiteralPath $file -Force -ErrorAction Stop
                    $RemovedList.Add($file) | Out-Null
                }
            }
            catch {
                $failedItems.Add("$Label`: $file :: $($_.Exception.Message)") | Out-Null
            }
        }
    }

    Remove-FileGroup -Files $DirectDisks          -RemovedList $removedDirectDisks          -Label 'DIRECT-DISK'
    Remove-FileGroup -Files $SidecarFiles         -RemovedList $removedSidecarFiles         -Label 'SIDECAR'
    Remove-FileGroup -Files $VMConfigRuntimeFiles -RemovedList $removedVMConfigRuntimeFiles -Label 'VM-CONFIG-RUNTIME'

    if ($DeleteFolderScanCandidates) {
        Remove-FileGroup -Files $FolderScanCandidates -RemovedList $removedFolderCandidates -Label 'FOLDER-CANDIDATE'
    }

    # Step 8.6.2: Remove eligible empty folders deepest first. A child
    # such as <VM>\Virtual Machines must be removed before its parent <VM>.
    # Only folders from the target VM inventory are eligible; never traverse
    # upwards to remove their parents or recursively delete folder contents.
    $eligibleFolders = @($Folders |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object -Unique |
        Sort-Object -Property @{ Expression = { ($_.TrimEnd('\','/') -split '[\\/]').Count }; Descending = $true }, @{ Expression = { $_ }; Descending = $true })

    # Add ancestors ONLY through an explicitly named VM root under a CSV volume.
    # This pass is empty-directory-only and cannot cross the CSV volume boundary.
    # Do not infer ownership from a generic directory such as "Virtual Hard Disks".
    $parentCandidates = New-Object 'System.Collections.Generic.List[string]'
    if (-not [string]::IsNullOrWhiteSpace($VMShortName)) {
        foreach ($sourceFolder in @($Folders)) {
            if ([string]::IsNullOrWhiteSpace($sourceFolder)) { continue }
            $cursor = $sourceFolder.TrimEnd('\', '/')
            $vmRootFound = $false
            $chain = New-Object 'System.Collections.Generic.List[string]'
            while ($cursor -match '(?i)^[A-Z]:\\ClusterStorage\\Volume[^\\]+\\.+') {
                $chain.Add($cursor) | Out-Null
                if ((Split-Path -Path $cursor -Leaf) -ieq $VMShortName) {
                    $vmRootFound = $true
                    break
                }
                $parent = Split-Path -Path $cursor -Parent
                if ([string]::IsNullOrWhiteSpace($parent) -or $parent -ieq $cursor) { break }
                $cursor = $parent
            }
            if ($vmRootFound) {
                foreach ($candidate in $chain) { $parentCandidates.Add($candidate) | Out-Null }

                # Step 9.5.5: Nested layouts may repeat the short VM name:
                # <CSV>\<VMShortName>\<VMShortName>\Virtual Hard Disks.
                # Continue through consecutive same-name parent directories only.
                # Never add the CSV volume root or an unrelated parent directory.
                $outerCursor = Split-Path -Path $cursor -Parent
                while (
                    -not [string]::IsNullOrWhiteSpace($outerCursor) -and
                    $outerCursor -match '(?i)^[A-Z]:\\ClusterStorage\\Volume[^\\]+\\.+$' -and
                    (Split-Path -Path $outerCursor -Leaf) -ieq $VMShortName
                ) {
                    $parentCandidates.Add($outerCursor) | Out-Null
                    $nextParent = Split-Path -Path $outerCursor -Parent
                    if ($nextParent -ieq $outerCursor) { break }
                    $outerCursor = $nextParent
                }
            }
        }
    }
    $eligibleFolders = @(@($eligibleFolders) + @($parentCandidates) |
        Sort-Object -Unique |
        Sort-Object -Property @{ Expression = { ($_.TrimEnd('\','/') -split '[\\/]').Count }; Descending = $true }, @{ Expression = { $_ }; Descending = $true })

    foreach ($folder in $eligibleFolders) {
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) { continue }
        $normalized = $folder.TrimEnd('\', '/')
        $leaf = Split-Path -Path $normalized -Leaf
        $pathRoot = [System.IO.Path]::GetPathRoot($folder)
        $isRoot = (-not [string]::IsNullOrWhiteSpace($pathRoot)) -and
            ($normalized -ieq $pathRoot.TrimEnd('\', '/'))

        # Never remove filesystem, CSV or conventional shared storage roots.
        # 'Virtual Machines' is intentionally NOT blocked by name: the
        # inventory can contain <specific VM>\Virtual Machines, which is safe
        # to remove *only when empty*. Generic shared locations are excluded.
        if ($isRoot -or $leaf -in @('Hyper-V','ClusterStorage') -or
            ($leaf -ieq 'Virtual Hard Disks' -and $parentCandidates -notcontains $folder) -or
            $normalized -match '(?i)^[A-Z]:\\ClusterStorage\\Volume[^\\]+$') {
            continue
        }
        try {
            $remaining = @(Get-ChildItem -LiteralPath $folder -Force -ErrorAction Stop)
            if ($remaining.Count -eq 0) {
                Remove-Item -LiteralPath $folder -Force -ErrorAction Stop
                $removedFolders.Add($folder) | Out-Null
            }
        } catch {
            $failedItems.Add("FOLDER: $folder :: $($_.Exception.Message)") | Out-Null
        }
    }

    return [pscustomobject]@{
        RemovedDirectDisks          = @($removedDirectDisks)
        RemovedSidecarFiles         = @($removedSidecarFiles)
        RemovedVMConfigRuntimeFiles = @($removedVMConfigRuntimeFiles)
        RemovedFolderCandidates     = @($removedFolderCandidates)
        RemovedFolders              = @($removedFolders)
        FailedItems                 = @($failedItems)
    }
}

