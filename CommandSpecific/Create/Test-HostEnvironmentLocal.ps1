# Purpose: Test-HostEnvironmentLocal - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Checks host Environment Local for the calling workflow.
function Test-HostEnvironmentLocal {
    param(
        [Parameter(Mandatory = $true)][pscustomobject]$Item
    )


    $result = [ordered]@{
        Errors   = New-Object System.Collections.ArrayList
        Warnings = New-Object System.Collections.ArrayList
    }

    try {
        if (-not (Test-PathCreatableLocal -PathValue $Item.DestinationRoot)) {
            [void]$result.Errors.Add("Destination root is not reachable/creatable on local host '$env:COMPUTERNAME': $($Item.DestinationRoot)")
        }

        $effectiveFolderName = if ([string]::IsNullOrWhiteSpace($Item.FolderNameOverride)) { $Item.BaseVMName } else { $Item.FolderNameOverride.Trim() }
        $vmFolder = Join-Path -Path $Item.DestinationRoot -ChildPath $effectiveFolderName
        $folderCheck = Test-HVVMFolderVacancy -Path $vmFolder
        foreach ($errorMessage in $folderCheck.Errors) { [void]$result.Errors.Add($errorMessage) }

        foreach ($disk in $Item.DiskDefinitions) {
            if (-not $disk.IsDefined) { continue }

            switch ($disk.Action) {
                'InPlace' {
                    if (-not (Test-Path -LiteralPath $disk.InPlace)) {
                        [void]$result.Errors.Add("Disk $($disk.Letter), InPlace VHDX not found on local host '$env:COMPUTERNAME': $($disk.InPlace)")
                        continue
                    }
                    try {
                        $currentBytes = Get-VhdVirtualSizeBytesSafe -Path $disk.InPlace
                        if ($null -ne $disk.NewSizeIncrToGB) {
                            $targetBytes = [int64]$disk.NewSizeIncrToGB * 1GB
                            if ($targetBytes -gt $currentBytes) {
                                [void]$result.Warnings.Add("Disk $($disk.Letter): InPlace VHDX will be expanded from $([math]::Ceiling($currentBytes/1GB)) GB to $($disk.NewSizeIncrToGB) GB: $($disk.InPlace)")
                            }
                            elseif ($targetBytes -lt $currentBytes) {
                                [void]$result.Warnings.Add("Disk $($disk.Letter): New Size Incr.to ($($disk.NewSizeIncrToGB) GB) is smaller than current VHDX size ($([math]::Ceiling($currentBytes/1GB)) GB). Shrinking is not supported; value will be ignored.")
                            }
                        }
                    }
                    catch {
                        [void]$result.Errors.Add("Could not read InPlace VHDX '$($disk.InPlace)'. $($_.Exception.Message)")
                    }
                }

                'CopySource' {
                    if (-not (Test-Path -LiteralPath $disk.Source)) {
                        [void]$result.Errors.Add("Disk $($disk.Letter), Source VHDX not found on local host '$env:COMPUTERNAME': $($disk.Source)")
                        continue
                    }
                    if (-not (Test-PathCreatableLocal -PathValue $disk.Layout.DiskRootPath)) {
                        [void]$result.Errors.Add("Disk $($disk.Letter) destination folder is not reachable/creatable on local host '$env:COMPUTERNAME': $($disk.Layout.DiskRootPath)")
                    }
                    if (Test-Path -LiteralPath $disk.Layout.DiskPath) {
                        [void]$result.Errors.Add("Disk $($disk.Letter) destination VHDX already exists: $($disk.Layout.DiskPath)")
                    }
                    try {
                        $currentBytes = Get-VhdVirtualSizeBytesSafe -Path $disk.Source
                        if ($null -ne $disk.NewSizeIncrToGB) {
                            $targetBytes = [int64]$disk.NewSizeIncrToGB * 1GB
                            if ($targetBytes -gt $currentBytes) {
                                [void]$result.Warnings.Add("Disk $($disk.Letter): copied source VHDX will be expanded from $([math]::Ceiling($currentBytes/1GB)) GB to $($disk.NewSizeIncrToGB) GB after copy.")
                            }
                            elseif ($targetBytes -lt $currentBytes) {
                                [void]$result.Warnings.Add("Disk $($disk.Letter): New Size Incr.to ($($disk.NewSizeIncrToGB) GB) is smaller than source VHDX size ($([math]::Ceiling($currentBytes/1GB)) GB). Shrinking is not supported; value will be ignored.")
                            }
                        }
                    }
                    catch {
                        [void]$result.Errors.Add("Could not read source VHDX '$($disk.Source)'. $($_.Exception.Message)")
                    }
                    if ($null -ne $disk.Layout.DiskSubfolder) {
                        Test-PathStringSegments -PathValue $disk.Layout.DiskSubfolder -FieldLabel "$($disk.Letter), V.Disks Folder" -Errors $result.Errors
                    }
                }

                'MoveSource' {
                    if (-not (Test-Path -LiteralPath $disk.Source)) {
                        [void]$result.Errors.Add("Disk $($disk.Letter), Source VHDX not found on local host '$env:COMPUTERNAME': $($disk.Source)")
                        continue
                    }
                    if (-not (Test-PathCreatableLocal -PathValue $disk.Layout.DiskRootPath)) {
                        [void]$result.Errors.Add("Disk $($disk.Letter) destination folder is not reachable/creatable on local host '$env:COMPUTERNAME': $($disk.Layout.DiskRootPath)")
                    }
                    if (Test-Path -LiteralPath $disk.Layout.DiskPath) {
                        [void]$result.Errors.Add("Disk $($disk.Letter) destination VHDX already exists: $($disk.Layout.DiskPath)")
                    }
                    [void]$result.Warnings.Add("Disk $($disk.Letter): MOVE mode is enabled. Source VHDX will be moved from '$($disk.Source)' to '$($disk.Layout.DiskPath)' instead of copied.")
                    try {
                        $currentBytes = Get-VhdVirtualSizeBytesSafe -Path $disk.Source
                        if ($null -ne $disk.NewSizeIncrToGB) {
                            $targetBytes = [int64]$disk.NewSizeIncrToGB * 1GB
                            if ($targetBytes -gt $currentBytes) {
                                [void]$result.Warnings.Add("Disk $($disk.Letter): moved source VHDX will be expanded from $([math]::Ceiling($currentBytes/1GB)) GB to $($disk.NewSizeIncrToGB) GB after move.")
                            }
                            elseif ($targetBytes -lt $currentBytes) {
                                [void]$result.Warnings.Add("Disk $($disk.Letter): New Size Incr.to ($($disk.NewSizeIncrToGB) GB) is smaller than source VHDX size ($([math]::Ceiling($currentBytes/1GB)) GB). Shrinking is not supported; value will be ignored.")
                            }
                        }
                    }
                    catch {
                        [void]$result.Errors.Add("Could not read source VHDX '$($disk.Source)'. $($_.Exception.Message)")
                    }
                    if ($null -ne $disk.Layout.DiskSubfolder) {
                        Test-PathStringSegments -PathValue $disk.Layout.DiskSubfolder -FieldLabel "$($disk.Letter), V.Disks Folder" -Errors $result.Errors
                    }
                }

                'New' {
                    if (-not (Test-PathCreatableLocal -PathValue $disk.Layout.DiskRootPath)) {
                        [void]$result.Errors.Add("Disk $($disk.Letter) destination folder is not reachable/creatable on local host '$env:COMPUTERNAME': $($disk.Layout.DiskRootPath)")
                    }
                    if (Test-Path -LiteralPath $disk.Layout.DiskPath) {
                        [void]$result.Errors.Add("Disk $($disk.Letter) destination VHDX already exists: $($disk.Layout.DiskPath)")
                    }
                    if ($null -ne $disk.Layout.DiskSubfolder) {
                        Test-PathStringSegments -PathValue $disk.Layout.DiskSubfolder -FieldLabel "$($disk.Letter), V.Disks Folder" -Errors $result.Errors
                    }
                }
            }
        }
    }
    catch {
        [void]$result.Errors.Add("Could not validate paths on local host '$env:COMPUTERNAME'. $($_.Exception.Message)")
    }

    foreach ($net in $Item.NetworkDefinitions) {
        if ([string]::IsNullOrWhiteSpace($net.SwitchName)) { continue }
        try {
            $sw = Get-VMSwitch -Name $net.SwitchName.Trim() -ErrorAction SilentlyContinue
            if (-not $sw) {
                [void]$result.Errors.Add("Network_$($net.Index) switch not found on local host '$env:COMPUTERNAME': $($net.SwitchName)")
            }
        }
        catch {
            [void]$result.Errors.Add("Could not validate Network_$($net.Index) on local host '$env:COMPUTERNAME'. $($_.Exception.Message)")
        }
    }

    [pscustomobject]$result
}
