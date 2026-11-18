# Purpose: New-HVVMFromTemplate - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Creates hVVMFrom Template for the calling workflow.
function New-HVVMFromTemplate {
    param(
        [pscustomobject]$Item,
        [switch]$AllowDuplicateBaseVMName
    )

    Import-Module Hyper-V -ErrorAction Stop


    $baseVMName          = $Item.BaseVMName
    $targetDisplayVMName = $Item.TargetDisplayVMName
    $effectiveFolderName = if ([string]::IsNullOrWhiteSpace($Item.FolderNameOverride)) { $baseVMName } else { $Item.FolderNameOverride.Trim() }
    $vmConfigRoot        = Join-Path -Path $Item.DestinationRoot -ChildPath $effectiveFolderName
    $vmConfigParentPath  = Split-Path -Path $vmConfigRoot -Parent
    $diskC               = $Item.DiskDefinitions | Where-Object { $_.Letter -eq 'C' } | Select-Object -First 1

    $existingBaseVM = Get-VM -Name $baseVMName -ErrorAction SilentlyContinue

    if ($existingBaseVM -and -not $AllowDuplicateBaseVMName) {
        throw "A VM named '$baseVMName' already exists on '$env:COMPUTERNAME'."
    }

    # New-VM -Path creates a child directory named after -Name. To make the
    # effective folder the final configuration directory, use its name for
    # initial creation, then rename the VM to its requested display name.
    # This is independent of -AllowDuplicateBaseVMName.
    $createVMName = $effectiveFolderName
    if ($existingBaseVM -and $AllowDuplicateBaseVMName) {
        if ($targetDisplayVMName.Trim().ToUpperInvariant() -eq $baseVMName.Trim().ToUpperInvariant()) {
            throw "A VM named '$baseVMName' already exists on '$env:COMPUTERNAME', and target display name is not different. Use a unique VM Description / target display name."
        }
    }

    # A VM with the folder name would prevent using that name for the initial
    # New-VM call. Fail before copying any disks rather than silently nesting.
    if (Get-VM -Name $createVMName -ErrorAction SilentlyContinue) {
        throw "Cannot create VM in folder '$vmConfigRoot': VM name '$createVMName' is already in use on '$env:COMPUTERNAME'. No disks were copied."
    }
    if ($createVMName -ne $targetDisplayVMName -and (Get-VM -Name $targetDisplayVMName -ErrorAction SilentlyContinue)) {
        throw "Target display VM name '$targetDisplayVMName' already exists on '$env:COMPUTERNAME'. No disks were copied."
    }

    Ensure-HVDirectory -Path $vmConfigRoot
    $newVMPath = $vmConfigParentPath
    Write-Host "VM folder: $vmConfigRoot"

    foreach ($disk in $Item.DiskDefinitions) {
        if (-not $disk.IsDefined) { continue }
        if ($disk.Action -eq 'InPlace') {
            Write-Host ("Final disk [{0}] action: InPlace -> {1}" -f $disk.Letter, $disk.InPlace)
        }
        else {
            Write-Host ("Final disk [{0}] action: {1} -> {2}" -f $disk.Letter, $disk.Action, $disk.Layout.DiskPath)
        }
    }

    $osDiskPath = Prepare-DiskPath -DiskDef $diskC

    $net1 = $Item.NetworkDefinitions | Where-Object { $_.Index -eq 1 } | Select-Object -First 1
    $newVmParams = @{
        Name               = $createVMName
        Generation         = $Item.Generation
        Path               = $newVMPath
        VHDPath            = $osDiskPath
        MemoryStartupBytes = ($Item.StartupRamMB * 1MB)
    }
    if ($net1 -and -not [string]::IsNullOrWhiteSpace($net1.SwitchName)) {
        $newVmParams['SwitchName'] = $net1.SwitchName.Trim()
    }

    Write-Host "Creating VM '$createVMName' on local host '$env:COMPUTERNAME'"
    New-VM @newVmParams | Out-Null
    Start-Sleep -Seconds 1

    $existingAdapters = @(Get-VMNetworkAdapter -VMName $createVMName)
    if ($existingAdapters.Count -ge 1) {
        $firstAdapter = $existingAdapters | Select-Object -First 1
        if ($firstAdapter.Name -ne 'Network Adapter 1') {
            Rename-VMNetworkAdapter -VMName $createVMName -Name $firstAdapter.Name -NewName 'Network Adapter 1' | Out-Null
        }
        if ($net1) {
            if ([string]::IsNullOrWhiteSpace($net1.SwitchName)) {
                Write-Host "Creating disconnected adapter 'Network Adapter 1'"
                Disconnect-VMNetworkAdapter -VMName $createVMName -Name 'Network Adapter 1' | Out-Null
            }
            else {
                Write-Host "Creating connected adapter 'Network Adapter 1' on switch '$($net1.SwitchName.Trim())'"
            }
        }
    }
    elseif ($net1) {
        if ([string]::IsNullOrWhiteSpace($net1.SwitchName)) {
            Write-Host "Creating disconnected adapter 'Network Adapter 1'"
            Add-VMNetworkAdapter -VMName $createVMName -Name 'Network Adapter 1' | Out-Null
        }
        else {
            Write-Host "Creating connected adapter 'Network Adapter 1' on switch '$($net1.SwitchName.Trim())'"
            Add-VMNetworkAdapter -VMName $createVMName -Name 'Network Adapter 1' -SwitchName $net1.SwitchName.Trim() | Out-Null
        }
    }

    foreach ($net in ($Item.NetworkDefinitions | Where-Object { $_.Index -gt 1 } | Sort-Object Index)) {
        if ([string]::IsNullOrWhiteSpace($net.SwitchName)) {
            Write-Host "Creating disconnected adapter '$($net.Name)'"
            Add-VMNetworkAdapter -VMName $createVMName -Name $net.Name | Out-Null
        }
        else {
            Write-Host "Creating connected adapter '$($net.Name)' on switch '$($net.SwitchName.Trim())'"
            Add-VMNetworkAdapter -VMName $createVMName -Name $net.Name -SwitchName $net.SwitchName.Trim() | Out-Null
        }
    }

    foreach ($net in $Item.NetworkDefinitions) {
        if ($null -ne $net.VlanId) {
            Set-VMNetworkAdapterVlan -VMName $createVMName -VMNetworkAdapterName $net.Name -Access -VlanId $net.VlanId | Out-Null
        }
    }

    Write-Host "Setting CPU count to $($Item.CpuCount)"
    Set-VMProcessor -VMName $createVMName -Count $Item.CpuCount | Out-Null

    if ($Item.DynamicRam -eq $true) {
        Write-Host "Enabling Dynamic Memory"
        Set-VMMemory -VMName $createVMName -DynamicMemoryEnabled $true -StartupBytes ($Item.StartupRamMB * 1MB) -MinimumBytes ($Item.MinRamMB * 1MB) -MaximumBytes ($Item.MaxRamMB * 1MB) | Out-Null
    }
    else {
        Write-Host "Disabling Dynamic Memory"
        Set-VMMemory -VMName $createVMName -DynamicMemoryEnabled $false -StartupBytes ($Item.StartupRamMB * 1MB) | Out-Null
    }

    if ($Item.Generation -eq 2) {
        if ($Item.SecureBoot -eq $true) {
            Write-Host "Enabling Secure Boot"
            Set-VMFirmware -VMName $createVMName -EnableSecureBoot On | Out-Null
        }
        elseif ($Item.SecureBoot -eq $false) {
            Write-Host "Disabling Secure Boot"
            Set-VMFirmware -VMName $createVMName -EnableSecureBoot Off | Out-Null
        }
    }

    foreach ($disk in ($Item.DiskDefinitions | Where-Object { $_.Letter -ne 'C' -and $_.IsDefined } | Sort-Object Letter)) {
        $dataDiskPath = Prepare-DiskPath -DiskDef $disk
        Add-VMHardDiskDrive -VMName $createVMName -Path $dataDiskPath | Out-Null
    }

    $timeSvc = Get-VMIntegrationService -VMName $createVMName -Name 'Time Synchronization' -ErrorAction SilentlyContinue
    if ($timeSvc) {
        if ($Item.TimeSyncEnabled -eq $true) {
            Enable-VMIntegrationService -VMName $createVMName -Name 'Time Synchronization' | Out-Null
        }
        elseif ($Item.TimeSyncEnabled -eq $false) {
            Disable-VMIntegrationService -VMName $createVMName -Name 'Time Synchronization' | Out-Null
        }
    }

    $guestSvc = Get-VMIntegrationService -VMName $createVMName -Name 'Guest Service Interface' -ErrorAction SilentlyContinue
    if ($guestSvc) {
        if ($Item.GuestSvcEnabled -eq $true) {
            Enable-VMIntegrationService -VMName $createVMName -Name 'Guest Service Interface' | Out-Null
        }
        elseif ($Item.GuestSvcEnabled -eq $false) {
            Disable-VMIntegrationService -VMName $createVMName -Name 'Guest Service Interface' | Out-Null
        }
    }

    if ($createVMName -ne $targetDisplayVMName) {
        Write-Host "Renaming VM display name to '$targetDisplayVMName'"
        Rename-VM -Name $createVMName -NewName $targetDisplayVMName | Out-Null
    }


    Write-Host "VM '$targetDisplayVMName' created successfully on local host '$env:COMPUTERNAME'." -ForegroundColor Green
}
