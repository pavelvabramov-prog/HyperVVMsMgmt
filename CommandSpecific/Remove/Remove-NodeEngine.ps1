# Purpose: Write-Info - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

<#
How to run:

IMPORTANT:
Run this script from an elevated PowerShell session ("Run as Administrator").

cd S:\00_Hyper-V\04_RemoveVms

If it's run from a network folder
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

.\Remove-HyperVVM-Full_MultiVM_v2.2.ps1 -VmName HVTSTVM012 -ValidateOnly
.\Remove-HyperVVM-Full_MultiVM_v2.2.ps1 -VmName HVTSTVM012


.SYNOPSIS
    Removes one or more Hyper-V VMs from the LOCAL host, optionally including cluster role,
    VM data, and AD computer account.

.DESCRIPTION
    - Resolves actual local VM objects using SafeBoundary matching against the supplied base VM name(s).
    - Example:
        Input parameter  : HVTSTVM001
        Actual VM object : HVTSTVM001 (Test VM)
      This is considered a safe match.

    Version v2.2 notes:
    - Keeps v2.1 cleanup behavior.
    - Fixes VM config/runtime reporting when Remove-VM already removed those files.

    Workflow per VM:
    1) Resolve actual local VM object by SafeBoundary logic.
    2) Check whether the VM is clustered and inventory cluster resources.
    3) Inventory VM files/folders and VHD/VHDX files.
    4) Check for AD computer account (using the VM computer-name token).
    5) If -ValidateOnly: stop after reporting.
    6) If apply mode:
         - ask for confirmation unless -Y
         - remove cluster role
         - remove VM
         - remove VM data
         - remove AD computer account
         - report everything removed

.NOTES
    Intended for LOCAL HOST execution.
    Hyper-V module is required.
    FailoverClusters and ActiveDirectory modules are optional but used when available.

    In practice, you should run this in an elevated PowerShell session ("Run as Administrator")
    with sufficient Hyper-V / Cluster / AD permissions for the requested cleanup actions.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string[]]$VMName,

    [string]$ExpectedVMId,
    [string]$ExpectedVMName,
    [switch]$ValidateOnly,

    [switch]$Y,

    # Deletes folder-scan candidate files without the extra safety confirmation.
    # Normal -Y does NOT bypass this extra confirmation.
    [switch]$ForceFolderCleanup,
    [switch]$ClusterRoleHandledExternally,
    [switch]$ADHandledExternally,
    [string]$InspectionContext = 'Validation'
)

# -----------------------------
# Output helpers
# -----------------------------
function Write-Info {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
}

# Writes warn Msg for the calling workflow.
function Write-WarnMsg {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Yellow
}

# Writes ok for the calling workflow.
function Write-Ok {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Green
}

# Writes err Msg for the calling workflow.
function Write-ErrMsg {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Red
}

# Writes folder Candidate for the calling workflow.
function Write-FolderCandidate {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Magenta
}

# -----------------------------
# SafeBoundary matching
# -----------------------------
# HV_STEP5_NODE_ASSESSMENT_FUNCTIONS

# -----------------------------
# Cluster helpers
# -----------------------------
# HV_STEP6_Get-ClusterVMInfo


# HV_STEP6_Test-ClusterRoleGone


# HV_STEP7_Remove-ClusterRoleSafe
# -----------------------------
# AD helpers
# -----------------------------
# HV_STEP6_Get-ADComputerInfoSafe


# -----------------------------
# Path helpers
# -----------------------------
# HV_STEP6_Add-UniqueString


# HV_STEP6_Get-VMDataInventory


# HV_STEP6_Test-FileLocked


# HV_STEP7_Wait-VMFileHandlesReleased
# HV_STEP7_Remove-VMDataSafe
# -----------------------------
# Main
# -----------------------------
try {
    Import-Module Hyper-V -ErrorAction Stop | Out-Null
}
catch {
    throw "Hyper-V module is required. $($_.Exception.Message)"
}

$executionMode = if ($ValidateOnly) { "ValidateOnly" } else { "ApplyMode" }
$stageLabel = if ($ValidateOnly) {
    if ($InspectionContext -eq 'PreRemoval') { 'Pre-removal inspection (read-only)' }
    else { 'Validation inspection (read-only)' }
} else { 'VM and storage deletion (Apply)' }
$localHost = $env:COMPUTERNAME

$batchSummary = New-Object 'System.Collections.Generic.List[object]'

foreach ($vmInputRaw in $VMName) {
    $vmInput = [string]$vmInputRaw
    if ([string]::IsNullOrWhiteSpace($vmInput)) {
        continue
    }

    $vmInput = $vmInput.Trim()

    # Apply-stage heading is printed on the initiating computer before cluster-role removal.
    # Keep the node-level heading for read-only inspection only.
    if ($ValidateOnly) {
        Write-Host ""
        Write-Host "============================================="
        Write-Host "$vmInput"
        Write-Host "Stage: $stageLabel | Host: $localHost" -ForegroundColor Cyan
        Write-Host "============================================="
    }

    $summaryStatus = "UNKNOWN"
    $summaryNotes  = ""
    $resolvedVmName = $null

    try {
        if ([string]::IsNullOrWhiteSpace($ExpectedVMId) -or [string]::IsNullOrWhiteSpace($ExpectedVMName)) {
            throw 'Selected VM identity was not supplied to node engine; refusing to continue.'
        }
        $vmCandidates = @(Get-VM -ErrorAction Stop | Where-Object { [string]$_.Id -eq $ExpectedVMId })
        if ($vmCandidates.Count -ne 1 -or $vmCandidates[0].Name -cne $ExpectedVMName) {
            throw "Selected VM ID/name not found on this node or changed: $ExpectedVMId / $ExpectedVMName. Refusing to continue."
        }
        $vm = $vmCandidates[0]
        $resolvedVmName = $vm.Name
        $computerName = if ($ADHandledExternally) { '(AD managed on initiating computer)' } else { Get-ComputerNameFromVMDisplayName -DisplayName $vm.Name -OriginalInputName $vmInput }

        $clusterInfo = Get-ClusterVMInfo -VM $vm
        $dataInventory = Get-VMDataInventory -VM $vm
        Write-Host ("Target VM ID : {0}" -f $dataInventory.VMId)
        $adInfo = if ($ADHandledExternally) { [pscustomobject]@{ ADModuleAvailable=$false; Found=$false; Computer=$null; Error=$null } } else { Get-ADComputerInfoSafe -ComputerName $computerName }
        Write-Host ("VM           : {0}" -f $vm.Name)
        Write-Host ("State        : {0}" -f $vm.State)
        Write-Host 'VM Match     : Selected VM ID (verified)'
        if ($clusterInfo.IsClustered) {
            Write-Host ("Cluster Role : {0}" -f $clusterInfo.ClusterGroup.Name)
        } elseif (-not $clusterInfo.ClusterModuleAvailable -and -not $vm.IsClustered) {
            Write-Host 'Cluster Role : N/A (standalone host)'
        } elseif (-not $clusterInfo.ClusterModuleAvailable) {
            Write-WarnMsg 'Cluster Role : Not verified (module unavailable)'
        } else { Write-Host 'Cluster Role : None' }
        foreach ($err in @($clusterInfo.Errors)) { Write-WarnMsg "Cluster check: $err" }
        $disks = @($dataInventory.DirectDisks | Sort-Object -Unique)
        Write-Host ("VHDX ({0}):" -f $disks.Count)
        foreach ($file in $disks) { Write-Host "  $file" }
        Write-Host ("Config files : {0}" -f @($dataInventory.VMConfigRuntimeFiles).Count)
        Write-Host ("Extra files  : {0}" -f @($dataInventory.FolderScanCandidates).Count)
        if ($dataInventory.FolderScanCandidates.Count -gt 0) {
            foreach ($file in ($dataInventory.FolderScanCandidates | Sort-Object -Unique)) { Write-FolderCandidate "  EXTRA: $file" }
        }
        Write-Host 'Folders considered for cleanup:'
        foreach ($folder in ($dataInventory.Folders | Sort-Object -Unique)) { Write-Host "  $folder" }
        if (-not $ADHandledExternally) {
            if ($adInfo.Found) { Write-Host "AD Account   : $computerName (Found)" }
            elseif ($adInfo.ADModuleAvailable) { Write-Host "AD Account   : $computerName (Not found)" }
            else { Write-WarnMsg 'AD Account   : Not checked (AD module unavailable)' }
        }
        Write-Host ''

        if ($ValidateOnly) {
            Write-Host "Result:"
            Write-Host " - Inspection completed (no changes)" -ForegroundColor Cyan
            $summaryStatus = "VALIDATED"
            $summaryNotes  = "Inventory/report only"
            $batchSummary.Add([pscustomobject]@{
                InputVM     = $vmInput
                ResolvedVM  = $resolvedVmName
                Status      = $summaryStatus
                Notes       = $summaryNotes
            }) | Out-Null
            continue
        }

        Write-Host "Result:"
        Write-Host " - Deletion stage (changes authorized)"

        if (-not $Y) {
            $answer = Read-Host "Type Y to remove VM '$($vm.Name)', its data, and its AD computer account"
            if ($answer -notmatch '^[Yy]$') {
                Write-WarnMsg "Operation cancelled by user."
                $summaryStatus = "CANCELLED"
                $summaryNotes  = "User did not confirm"
                $batchSummary.Add([pscustomobject]@{
                    InputVM     = $vmInput
                    ResolvedVM  = $resolvedVmName
                    Status      = $summaryStatus
                    Notes       = $summaryNotes
                }) | Out-Null
                continue
            }
        }

        $report = [ordered]@{
            ClusterRoleRemoved = @()
            VMRemoved          = @()
            DirectDisksRemoved          = @()
            SidecarFilesRemoved         = @()
            VMConfigRuntimeFilesRemoved = @()
            FolderCandidatesRemoved     = @()
            FoldersRemoved              = @()
            ADRemoved          = @()
            Warnings           = @()
        }

        if (-not $ClusterRoleHandledExternally -and $clusterInfo.ClusterModuleAvailable -and $clusterInfo.IsClustered -and $clusterInfo.ClusterGroup) {
            try {
                $clusterGroupNameForVerify = $clusterInfo.ClusterGroup.Name
                $clusterRemoval = Remove-ClusterRoleSafe -ClusterGroup $clusterInfo.ClusterGroup
                foreach ($d in $clusterRemoval.Details) {
                    $report.ClusterRoleRemoved += $d
                }

                Write-Info "Verifying cluster role cleanup..."
                Start-Sleep -Seconds 3
                $remainingClusterItems = @(Test-ClusterRoleGone -ClusterGroupName $clusterGroupNameForVerify)

                if ($remainingClusterItems.Count -gt 0) {
                    foreach ($item in $remainingClusterItems) {
                        $report.Warnings += "CLUSTER CLEANUP WARNING: $item"
                    }
                    Write-WarnMsg "Cluster role removal attempted, but stale cluster objects may remain."
                }
                else {
                    Write-Ok "Cluster role removed and verified."
                }
            }
            catch {
                throw "Failed to remove cluster role: $($_.Exception.Message)"
            }
        }
        else {
            if (-not $ClusterRoleHandledExternally -and $clusterInfo.IsClustered) {
        $report.Warnings += "Cluster role removal not required or cluster role not detected."
    }
        }

        try {
            $vmStateNow = (Get-VM -Id $vm.Id -ErrorAction Stop).State
            if ($vmStateNow -ne 'Off') {
                Write-Info "Stopping VM '$($vm.Name)'..."
                Stop-VM -VM $vm -TurnOff -Force -ErrorAction Stop | Out-Null
            }
        }
        catch {
            $report.Warnings += "Unable to stop VM cleanly before removal: $($_.Exception.Message)"
        }

        try {
            Write-Info "Removing VM '$($vm.Name)'..."
            Remove-VM -VM $vm -Force -ErrorAction Stop
            $report.VMRemoved += "VM '$($vm.Name)' removed."
            Write-Ok "VM removed."
        }
        catch {
            throw "Failed to remove VM: $($_.Exception.Message)"
        }

        $folderCleanupApproved = $false

        if ($dataInventory.FolderScanCandidates.Count -gt 0) {
            if ($ForceFolderCleanup) {
                $folderCleanupApproved = $true
                Write-WarnMsg "-ForceFolderCleanup specified. Folder-scan candidate files will be deleted."
            }
            else {
                Write-FolderCandidate "Folder-scan candidate files were found. These may include unrelated files."
                foreach ($candidate in ($dataInventory.FolderScanCandidates | Sort-Object -Unique)) {
                    Write-FolderCandidate " - $candidate"
                }

                $folderAnswer = Read-Host "Type Y to also delete folder-scan candidate files"
                if ($folderAnswer -match '^[Yy]$') {
                    $folderCleanupApproved = $true
                }
                else {
                    $report.Warnings += "Folder-scan candidate files were not deleted. Use -ForceFolderCleanup or answer Y to the extra prompt to delete them."
                }
            }
        }

        $targetedFilesForWait = @(
            @($dataInventory.DirectDisks) +
            @($dataInventory.SidecarFiles) +
            @($dataInventory.VMConfigRuntimeFiles) +
            $(if ($folderCleanupApproved) { @($dataInventory.FolderScanCandidates) } else { @() })
        )

        $lockedFiles = @(Wait-VMFileHandlesReleased -Files $targetedFilesForWait)
        $unlockedFiles = @($targetedFilesForWait | Where-Object { $lockedFiles -notcontains $_ })
        if ($lockedFiles.Count -gt 0) {
            foreach ($lockedFile in $lockedFiles) { $report.Warnings += "LOCKED - NOT REMOVED: $lockedFile" }
        }

        $dataRemoval = Remove-VMDataSafe `
            -DirectDisks @($dataInventory.DirectDisks | Where-Object { $lockedFiles -notcontains $_ }) `
            -SidecarFiles @($dataInventory.SidecarFiles | Where-Object { $lockedFiles -notcontains $_ }) `
            -VMConfigRuntimeFiles @($dataInventory.VMConfigRuntimeFiles | Where-Object { $lockedFiles -notcontains $_ }) `
            -FolderScanCandidates @($dataInventory.FolderScanCandidates | Where-Object { $lockedFiles -notcontains $_ }) `
            -Folders $dataInventory.Folders `
            -VMShortName $vmInput `
            -DeleteFolderScanCandidates:$folderCleanupApproved

        if ($dataRemoval.RemovedDirectDisks.Count -gt 0) {
            $report.DirectDisksRemoved += $dataRemoval.RemovedDirectDisks
        }
        if ($dataRemoval.RemovedSidecarFiles.Count -gt 0) {
            $report.SidecarFilesRemoved += $dataRemoval.RemovedSidecarFiles
        }
        if ($dataRemoval.RemovedVMConfigRuntimeFiles.Count -gt 0) {
            $report.VMConfigRuntimeFilesRemoved += $dataRemoval.RemovedVMConfigRuntimeFiles
        }
        if ($dataRemoval.RemovedFolderCandidates.Count -gt 0) {
            $report.FolderCandidatesRemoved += $dataRemoval.RemovedFolderCandidates
        }
        if ($dataRemoval.RemovedFolders.Count -gt 0) {
            $report.FoldersRemoved += $dataRemoval.RemovedFolders
        }
        if ($dataRemoval.FailedItems.Count -gt 0) {
            $report.Warnings += $dataRemoval.FailedItems
        }

if ($ADHandledExternally) {
    # AD is handled and reported by the initiating computer; not a node-side warning.
}
elseif ($adInfo.ADModuleAvailable -and $adInfo.Found -and $adInfo.Computer) {
    try {
        Write-Info "Removing AD computer account '$computerName'..."
        Remove-ADComputer -Identity $adInfo.Computer -Confirm:$false -ErrorAction Stop
        $report.ADRemoved += "AD computer '$computerName' removed from '$($adInfo.Computer.DistinguishedName)'."
        Write-Ok "AD computer account removed."
    }
    catch {
        $adRemoveError = $_.Exception.Message

        if ($adRemoveError -match 'leaf object') {
            try {
                Write-WarnMsg "AD computer object is not a leaf object. Retrying with recursive AD removal..."
                Remove-ADObject -Identity $adInfo.Computer.DistinguishedName -Recursive -Confirm:$false -ErrorAction Stop
                $report.ADRemoved += "AD computer '$computerName' removed recursively from '$($adInfo.Computer.DistinguishedName)'."
                Write-Ok "AD computer account removed recursively."
            }
            catch {
                $report.Warnings += "Failed to remove AD computer '$computerName' recursively: $($_.Exception.Message)"
            }
        }
        else {
            $report.Warnings += "Failed to remove AD computer '$computerName': $adRemoveError"
        }
    }
}
elseif ($adInfo.ADModuleAvailable -and -not $adInfo.Found) {
    $report.Warnings += "AD computer '$computerName' was not found, so nothing was removed from AD."
}
else {
    $report.Warnings += "AD module unavailable, so AD removal was skipped."
}

        # The initiating computer prints the verified FINAL REPORT after AD cleanup.
        # Keep the node report only for standalone engine execution.
        if (-not $ADHandledExternally) {
        Write-Host ""
        Write-Host "================ FINAL REPORT ================"

        Write-Host ""
        Write-Host "Cluster role removed:"
        if ($report.ClusterRoleRemoved.Count -gt 0) {
            foreach ($item in $report.ClusterRoleRemoved) {
                Write-Host " - $item"
            }
        }
        elseif ($ClusterRoleHandledExternally) {
            Write-Host " - Removed and verified on initiating computer (see consolidated result below)"
        }
        else {
            Write-Host " - No cluster role removed by this execution"
        }

        Write-Host ""
        Write-Host "VM removed:"
        if ($report.VMRemoved.Count -gt 0) {
            foreach ($item in $report.VMRemoved) {
                Write-Host " - $item"
            }
        }
        else {
            Write-WarnMsg " - Nothing removed"
        }

        Write-Host ""
        Write-Host "Direct VM disks removed:"
        if ($report.DirectDisksRemoved.Count -gt 0) {
            foreach ($item in $report.DirectDisksRemoved) {
                Write-Host " - $item"
            }
        }
        else {
            Write-WarnMsg " - Nothing removed"
        }

        Write-Host ""
        Write-Host "Additional disk-related files removed:"
        if ($report.SidecarFilesRemoved.Count -gt 0) {
            foreach ($item in $report.SidecarFilesRemoved) {
                Write-Host " - $item"
            }
        }
        elseif ($dataInventory.SidecarFiles.Count -eq 0) {
            Write-Host " - none found"
        }
        else {
            Write-WarnMsg " - Nothing removed"
        }

        Write-Host ""
        Write-Host "VM config/runtime files removed:"
        if ($report.VMConfigRuntimeFilesRemoved.Count -gt 0) {
            foreach ($item in $report.VMConfigRuntimeFilesRemoved) {
                Write-Host " - $item"
            }
        }
        elseif ($dataInventory.VMConfigRuntimeFiles.Count -eq 0) {
            Write-Host " - none found"
        }
        else {
            # v2.2 reporting fix:
            # Hyper-V commonly removes VM configuration/runtime files during Remove-VM.
            # If they were present in inventory but no longer exist at final report time,
            # do not report this as "Nothing removed" because it is misleading.
            $remainingVmConfigRuntimeFiles = @(
                $dataInventory.VMConfigRuntimeFiles |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_) }
            )

            if ($remainingVmConfigRuntimeFiles.Count -eq 0) {
                Write-Host " - already removed by Hyper-V or earlier cleanup"
            }
            else {
                Write-WarnMsg " - Not removed / still present:"
                foreach ($item in $remainingVmConfigRuntimeFiles) {
                    Write-WarnMsg "   - $item"
                }
            }
        }

        Write-Host ""
        Write-FolderCandidate "Other files removed:"
        if ($report.FolderCandidatesRemoved.Count -gt 0) {
            foreach ($item in $report.FolderCandidatesRemoved) {
                Write-FolderCandidate " - $item"
            }
        }
        elseif ($dataInventory.FolderScanCandidates.Count -eq 0) {
            Write-Host " - none found"
        }
        else {
            Write-WarnMsg " - Nothing removed"
        }

        Write-Host ""
        Write-Host "Folders removed:"
        if ($report.FoldersRemoved.Count -gt 0) {
            foreach ($item in $report.FoldersRemoved) {
                Write-Host " - $item"
            }
        }
        else {
            Write-WarnMsg " - Nothing removed"
        }

        Write-Host ""
        Write-Host "AD objects removed:"
        if ($report.ADRemoved.Count -gt 0) {
            foreach ($item in $report.ADRemoved) {
                Write-Host " - $item"
            }
        }
        else {
            Write-WarnMsg " - Nothing removed"
        }

        if ($report.Warnings.Count -gt 0) {
            Write-Host ""
            Write-WarnMsg "Warnings:"
            foreach ($item in $report.Warnings) {
                Write-WarnMsg " - $item"
            }
        }

        Write-Host ("Extra files   : {0} found, {1} removed" -f @($dataInventory.FolderScanCandidates).Count, @($report.FolderCandidatesRemoved).Count)
        Write-Host ("Locked files  : {0}" -f @($lockedFiles).Count)
        foreach ($lockedFile in $lockedFiles) { Write-WarnMsg "  $lockedFile" }
        Write-Host ""
        if ($report.Warnings.Count -gt 0) { Write-WarnMsg 'Operation completed with warnings (PARTIAL SUCCESS).' }
        else { Write-Ok 'Operation completed.' }

        }

        # v3.3: return actual removal results to the initiating computer.
        # This is an output-only addition; removal operations remain unchanged.
        [pscustomobject]@{
            PSTypeName = 'HyperVRemoval.NodeResult'
            ResultMarker = 'HyperVRemoval.NodeResult.v3.3'
            VMRemoved = @($report.VMRemoved)
            DirectDisksRemoved = @($report.DirectDisksRemoved)
            SidecarFilesRemoved = @($report.SidecarFilesRemoved)
            VMConfigRuntimeFilesRemoved = @($report.VMConfigRuntimeFilesRemoved)
            VMConfigRuntimeFilesInventoried = @($dataInventory.VMConfigRuntimeFiles)
            FolderCandidatesRemoved = @($report.FolderCandidatesRemoved)
            FoldersRemoved = @($report.FoldersRemoved)
            ADRemoved = @($report.ADRemoved)
            ExtraFilesFound = @($dataInventory.FolderScanCandidates).Count
            LockedFiles = @($lockedFiles)
            Warnings = @($report.Warnings)
        }

        $summaryStatus = "REMOVED"
        if ($report.Warnings.Count -gt 0) {
            $summaryNotes = "Removed with warnings"
        }
        else {
            $summaryNotes = "Removed successfully"
        }
    }
    catch {
        Write-ErrMsg "FAILED for '$vmInput': $($_.Exception.Message)"
        $summaryStatus = "FAILED"
        $summaryNotes  = $_.Exception.Message
        throw
    }

    $batchSummary.Add([pscustomobject]@{
        InputVM     = $vmInput
        ResolvedVM  = $resolvedVmName
        Status      = $summaryStatus
        Notes       = $summaryNotes
    }) | Out-Null
}

#Write-Host ""
#Write-Host "================ BATCH SUMMARY ================"
#$batchSummary | Format-Table -AutoSize

