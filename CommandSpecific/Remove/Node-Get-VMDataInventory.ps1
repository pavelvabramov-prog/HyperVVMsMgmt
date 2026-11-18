# Purpose: Get-VMDataInventory - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Retrieves vMData Inventory for the calling workflow.
function Get-VMDataInventory {
    param([Parameter(Mandatory=$true)]$VM)

    # Step 8.6: Only Hyper-V metadata may classify a file as belonging to the VM.
    # Folder membership and extensions NEVER establish ownership.
    $disks = New-Object 'System.Collections.Generic.List[string]'
    $sidecars = New-Object 'System.Collections.Generic.List[string]'
    $configs = New-Object 'System.Collections.Generic.List[string]'
    $extras = New-Object 'System.Collections.Generic.List[string]'
    $folders = New-Object 'System.Collections.Generic.List[string]'
    $ownedFolders = New-Object 'System.Collections.Generic.List[string]'
    $known = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $id = $VM.Id.ToString('D')
    if ([string]::IsNullOrWhiteSpace($id)) { throw 'VM ID is missing; cleanup is unsafe.' }

    # Fail closed: a failed Hyper-V disk query must not become an empty disk inventory.
    $drives = @(Get-VMHardDiskDrive -VM $VM -ErrorAction Stop)
    foreach ($drive in $drives) {
        if ([string]::IsNullOrWhiteSpace($drive.Path)) { continue }
        Add-UniqueString -List $disks -Value $drive.Path
    }
    # Checkpoint disks are VM metadata, not directory guesses.
    $snapshots = @(Get-VMSnapshot -VM $VM -ErrorAction Stop)
    foreach ($snapshot in $snapshots) {
        foreach ($drive in @(Get-VMHardDiskDrive -VMSnapshot $snapshot -ErrorAction Stop)) {
            if (-not [string]::IsNullOrWhiteSpace($drive.Path)) {
                Add-UniqueString -List $disks -Value $drive.Path
            }
        }
    }
    # Follow explicitly declared differencing parent links, if available.
    $queue = New-Object 'System.Collections.Generic.Queue[string]'
    foreach ($disk in $disks) { $queue.Enqueue($disk) }
    $visited = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    while ($queue.Count -gt 0) {
        $disk = $queue.Dequeue()
        if (-not $visited.Add($disk)) { continue }
        if (-not (Test-Path -LiteralPath $disk -PathType Leaf)) { continue }
        $vhd = Get-VHD -Path $disk -ErrorAction Stop
        if (-not [string]::IsNullOrWhiteSpace($vhd.ParentPath)) {
            # Parent VHDs can be shared templates: DO NOT delete them by default.
            # Report them as additional files, rather than as target-owned disks.
            $queue.Enqueue($vhd.ParentPath)
        }
    }
    foreach ($disk in @($disks)) {
        [void]$known.Add($disk)
        Add-UniqueString -List $folders -Value (Split-Path -Path $disk -Parent)
        foreach ($suffix in @('.rct','.mrt')) {
            $candidate = "$disk$suffix"
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                Add-UniqueString -List $sidecars -Value $candidate
                [void]$known.Add($candidate)
            }
        }
    }
    # Explicit VM-ID files only. Never classify all .vmcx/.vmrs/.vmgs by extension.
    foreach ($property in @('Path','ConfigurationLocation','SnapshotFileLocation','SmartPagingFilePath')) {
        if ($VM.PSObject.Properties.Name -notcontains $property) { continue }
        $location = [string]$VM.$property
        if ([string]::IsNullOrWhiteSpace($location)) { continue }
        if ([System.IO.Path]::HasExtension($location) -and (Test-Path -LiteralPath $location -PathType Leaf)) {
            if ($location -match [regex]::Escape($id)) {
                Add-UniqueString -List $configs -Value $location
                [void]$known.Add($location)
            }
            continue
        }
        if (-not (Test-Path -LiteralPath $location -PathType Container)) { continue }
        # Search only the declared location and its conventional Virtual Machines subdirectory.
        # No recursive search of shared Hyper-V parents.
        foreach ($dir in @($location, (Join-Path $location 'Virtual Machines'))) {
            if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
            foreach ($file in @(Get-ChildItem -LiteralPath $dir -Force -File -ErrorAction Stop)) {
                $stem = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                if ($stem -ieq $id -or $stem -ieq ('{' + $id + '}')) {
                    Add-UniqueString -List $configs -Value $file.FullName
                    [void]$known.Add($file.FullName)
                    Add-UniqueString -List $folders -Value $dir
                }
            }
        }
    }
    # Scan only directories containing positively identified VM files, and only
    # their immediate contents. All other files are extras, including other VMs' files.
    foreach ($folder in @($folders | Sort-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $folder -Force -File -ErrorAction Stop)) {
            if (-not $known.Contains($file.FullName)) {
                Add-UniqueString -List $extras -Value $file.FullName
            }
        }
    }
    return [pscustomobject]@{
        DirectDisks=@($disks); SidecarFiles=@($sidecars)
        VMConfigRuntimeFiles=@($configs); FolderScanCandidates=@($extras)
        Folders=@($folders); VMId=$id
    }
}
