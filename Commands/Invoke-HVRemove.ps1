# Purpose: Invoke-HVRemove - command entry point.
# Maintains the existing validation, logging, and execution behavior.

# Remove command: coordinates VM removal using the existing safety checks.
# Step 8: direct module-native remove command. No legacy script execution.
function Invoke-HVRemove {
    [CmdletBinding(DefaultParameterSetName='CommandLine')]
    param(
        [Parameter(ParameterSetName='CommandLine',Position=0)][string[]]$VMName,
        [Parameter(ParameterSetName='CommandLine')][string]$TargetHost,
        [Parameter(Mandatory=$true,ParameterSetName='ListFile')][string]$VMListFile,
        [switch]$ValidateOnly,
        [switch]$ResetADAccount,
        [switch]$KeepADAccount,
        [string]$ADNameToCleanUp,
        [switch]$Y,
        [switch]$ForceFolderCleanup,
        [switch]$ShowTiming,
        [switch]$Help
    )
    if ($Help -or ($VMName -contains '/?') -or ($args -contains '/?')) {
        Show-HVUsageHelp -Command Remove
        return
    }
    $removeSourceRoot = Join-Path $script:moduleRoot 'CommandSpecific\Remove'
$ErrorActionPreference = 'Stop'
if ($ForceFolderCleanup -and -not $Y) { throw '-ForceFolderCleanup requires -Y. No changes made.' }
if ($KeepADAccount -and $ResetADAccount) { throw '-KeepADAccount and -ResetADAccount cannot be used together. No changes made.' }
if ($PSBoundParameters.ContainsKey('ADNameToCleanUp')) {
    if ($KeepADAccount -or $PSBoundParameters.ContainsKey('VMListFile')) {
        throw '-ADNameToCleanUp cannot be used with -KeepADAccount or -VMListFile. No changes made.'
    }
    if ($VMName.Count -ne 1) { throw '-ADNameToCleanUp requires exactly one -VMName. No changes made.' }
    if ($ADNameToCleanUp -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,14}$' -or $ADNameToCleanUp -match '^[0-9]+$') {
        throw '-ADNameToCleanUp must be a valid AD computer sAMAccountName (1..15 characters, letters/digits/hyphens). No changes made.'
    }
}


# Load the module-owned, text-based configuration.
$settings = Get-HVModuleConfiguration
# The configured short-name regex is the sole source for implicit AD identity.
$adShortNamePattern = [string]$settings.VMNaming.ShortNamePattern
if ([string]::IsNullOrWhiteSpace($adShortNamePattern)) { throw 'VMNaming.ShortNamePattern is missing from module configuration.' }
try { $null = [regex]::new($adShortNamePattern) } catch { throw "Invalid configured VMNaming.ShortNamePattern: $($_.Exception.Message)" }
$logDir = if (-not [string]::IsNullOrWhiteSpace($settings.RemoveLogPath)) { $settings.RemoveLogPath } else { $settings.LogPath }
if ([string]::IsNullOrWhiteSpace($logDir) -or -not [System.IO.Path]::IsPathRooted($logDir)) { throw 'Invalid configured Remove log directory.' }
if (-not (Test-Path -LiteralPath $logDir -PathType Container)) { New-Item -ItemType Directory -Path $logDir -Force -ErrorAction Stop | Out-Null }
$stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$logFile = Join-Path $logDir ("Remove_{0}.log" -f $stamp)
$collision = 1
while (Test-Path -LiteralPath $logFile) {
    $logFile = Join-Path $logDir ("Remove_{0}_{1}.log" -f $stamp,$collision)
    $collision++
}
Start-Transcript -LiteralPath $logFile -ErrorAction Stop | Out-Null
trap {
    Write-Host "Remove v3.5.6 stopped: $($_.Exception.Message)" -ForegroundColor Red
    try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
    break
}
Write-Host "Remove v3.5.6 | Transcript: $logFile" -ForegroundColor Cyan
Invoke-HVTiming -Action Reset -Enabled:$ShowTiming

# Extracted to CommandSpecific/Remove/Read-RemovalList.ps1 (Step 2).

try {
    if ($PSCmdlet.ParameterSetName -eq 'ListFile') {
        $removalRequests = @(Read-RemovalList -Path $VMListFile)
    } else {
        if (-not $VMName -or @($VMName).Count -eq 0) { throw 'Invalid or missing parameter: specify -VMName and -TargetHost, or -VMListFile. Use hv-remove -Help for help.' }
        if ([string]::IsNullOrWhiteSpace($TargetHost)) { throw 'Invalid or missing parameter: -TargetHost is required with -VMName. Use hv-remove -Help for help.' }
        $removalRequests = @($VMName | ForEach-Object { [pscustomobject]@{Name=([string]$_).Trim();Host=$TargetHost.Trim();ADName='';Line=0} })
    }
    if (-not $removalRequests) { throw 'The VM removal list is empty.' }
    $keys = @{}
    foreach ($entry in $removalRequests) {
        if ([string]::IsNullOrWhiteSpace($entry.Name) -or [string]::IsNullOrWhiteSpace($entry.Host)) { throw 'Empty VM name or target host is not allowed.' }
        $key = ($entry.Host + '|' + $entry.Name).ToUpperInvariant()
        if ($keys.ContainsKey($key)) { throw "Duplicate removal request: $($entry.Name) on $($entry.Host)" }
        $keys[$key] = $true
    }
    Write-Host ("VMs to Remove : {0}" -f $removalRequests.Count)
    Write-Host ("Mode          : {0}" -f $(if($ValidateOnly){'ValidateOnly'}else{'Apply'}))
    Write-Host ("AD Action     : {0}" -f $(if($KeepADAccount){'KEEP'}elseif($ResetADAccount){'RESET'}else{'DELETE'}))
} catch {
    Write-Host ("ERROR: {0}" -f $_.Exception.Message) -ForegroundColor Red
    Write-Host 'No changes made.' -ForegroundColor Yellow
    try { Invoke-HVTiming -Action Report } catch { }
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
    return
}
# Original v2.2 engine, embedded unchanged except an internal flag that prevents
# attempting to remove cluster roles a second time after host-side registration removal.
# Step 4: keep the original node-local engine as source text, not as a dot-sourced script.
# It must be executed ONLY by Invoke-RemovalEngine, locally or on the target host.
$enginePath = Join-Path $removeSourceRoot 'Remove-NodeEngine.ps1'
if (-not (Test-Path -LiteralPath $enginePath -PathType Leaf)) {
    throw "Remove node engine source not found: $enginePath"
}
$engine = [System.IO.File]::ReadAllText($enginePath, [System.Text.Encoding]::UTF8)

# Step 5: insert node-local assessment functions into the source BEFORE
# the engine is dispatched to a remote node. Never dot-source these files.
$nodeAssessmentFunctions = @(
    'Test-SafeBoundaryMatch',
    'Resolve-VMBySafeBoundary',
    'Get-ComputerNameFromVMDisplayName'
)
$nodeAssessmentSource = foreach ($functionName in $nodeAssessmentFunctions) {
    $functionPath = Join-Path $removeSourceRoot ("Node-{0}.ps1" -f $functionName)
    if (-not (Test-Path -LiteralPath $functionPath -PathType Leaf)) {
        throw "Missing node assessment function source: $functionPath"
    }
    [System.IO.File]::ReadAllText($functionPath, [System.Text.Encoding]::UTF8)
}
$marker = '# HV_STEP5_NODE_ASSESSMENT_FUNCTIONS'
if (-not $engine.Contains($marker)) { throw 'Node assessment insertion marker not found.' }
$engine = $engine.Replace($marker, ($nodeAssessmentSource -join [Environment]::NewLine))

# Step 6: assemble read-only node-local inventory and lookup helpers.
# Source files are text, not imported into the jump-host module.
$nodeReadOnlyFunctions = @(
    'Get-ClusterVMInfo',
    'Test-ClusterRoleGone',
    'Get-ADComputerInfoSafe',
    'Add-UniqueString',
    'Get-VMDataInventory',
    'Test-FileLocked'
)
foreach ($functionName in $nodeReadOnlyFunctions) {
    $functionPath = Join-Path $removeSourceRoot ("Node-{0}.ps1" -f $functionName)
    if (-not (Test-Path -LiteralPath $functionPath -PathType Leaf)) {
        throw "Missing node-local function source: $functionPath"
    }
    $functionSource = [System.IO.File]::ReadAllText($functionPath, [System.Text.Encoding]::UTF8)
    $functionMarker = '# HV_STEP6_' + $functionName
    if (-not $engine.Contains($functionMarker)) {
        throw "Missing node-local insertion marker: $functionMarker"
    }
    $engine = $engine.Replace($functionMarker, $functionSource)
}

# Step 7: assemble the original destructive node-local functions unchanged.
# These remain source text until dispatched to the target host.
$nodeDestructiveFunctions = @(
    'Remove-ClusterRoleSafe',
    'Wait-VMFileHandlesReleased',
    'Remove-VMDataSafe'
)
foreach ($functionName in $nodeDestructiveFunctions) {
    $functionPath = Join-Path $removeSourceRoot ("Node-{0}.ps1" -f $functionName)
    if (-not (Test-Path -LiteralPath $functionPath -PathType Leaf)) {
        throw "Missing destructive function source: $functionPath"
    }
    $functionSource = [System.IO.File]::ReadAllText($functionPath, [System.Text.Encoding]::UTF8)
    $functionMarker = '# HV_STEP7_' + $functionName
    if (-not $engine.Contains($functionMarker)) {
        throw "Missing destructive function insertion marker: $functionMarker"
    }
    $engine = $engine.Replace($functionMarker, $functionSource)
}


# Extracted to CommandSpecific/Remove/Invoke-RemovalEngine.ps1 (Step 3).
# Extracted to CommandSpecific/Remove/Get-JumpHostADStatus.ps1 (Step 2).
# Extracted to CommandSpecific/Remove/Remove-JumpHostADComputer.ps1 (Step 2).
# Extracted to CommandSpecific/Remove/Test-Boundary.ps1 (Step 2).
# Extracted to CommandSpecific/Remove/Get-ClusterVMRoleById.ps1 (Step 2).
try {
# Validate ALL requested VMs before ANY destructive operation.
# In particular, reject ambiguous matches, unreachable targets, and repeated VM IDs.
Import-Module Hyper-V -ErrorAction Stop
$preflight = New-Object 'System.Collections.Generic.List[object]'
$seenIds = @{}
$selectionContext = New-HVSelectionContext
# Queue AD ambiguity warnings so a subsequent duplicate-entry warning is printed first.
# Confirmations remain in the complete preflight, before any destructive operation.
$pendingADWarnings = New-Object 'System.Collections.Generic.List[object]'
$shownADWarnings = @{}
$flushADWarnings = {
    foreach ($warningItem in $pendingADWarnings.ToArray()) {
        if (-not $shownADWarnings.ContainsKey($warningItem.Target)) {
            Write-Warning ("Resolved AD account '{0}' may be used by any of the following Hyper-V VMs: {1}" -f $warningItem.Target, ($warningItem.Names -join ', '))
            if ($ValidateOnly) {
                $actionLabel = if ($ResetADAccount) { 'RESET' } else { 'DELETE' }
                Write-Host "ValidateOnly: $actionLabel requires explicit confirmation in Apply mode; no changes made." -ForegroundColor Yellow
            }
            $shownADWarnings[$warningItem.Target] = $true
        }
    }
    if ($pendingADWarnings.Count -gt 0) { Write-Host '' }
    $pendingADWarnings.Clear()
}
foreach ($request in $removalRequests) {
    $target = $request.Host
    $cluster = $null
    $searchNodes = @($target)
    $targetType = 'Standalone'
    if (Get-Module -ListAvailable FailoverClusters) {
        Import-Module FailoverClusters -ErrorAction Stop
        try {
            $clusterObject = Get-Cluster -Name $target -ErrorAction Stop -WarningAction SilentlyContinue
            $cluster = $clusterObject.Name
            $searchNodes = @(Get-ClusterNode -Cluster $cluster -ErrorAction Stop -WarningAction SilentlyContinue | Where-Object State -eq 'Up' | Select-Object -ExpandProperty Name)
            if (-not $searchNodes) { throw "No online nodes for cluster '$cluster'" }
            $targetType = if (@($searchNodes | Where-Object { $_ -ieq $target }).Count -gt 0) { 'ClusterNode' } else { 'Cluster' }
        } catch {
            if ($cluster) { throw }
            $searchNodes = @($target)
        }
    }
    $hits = @()
    foreach ($n in $searchNodes) {
        try {
            $inventory = @(Invoke-HVTiming -Action Measure -TimingLabel 'Preflight Get-VM inventory' -Target $n -ScriptBlock { Get-VM -ComputerName $n -ErrorAction Stop })
            foreach ($candidate in $inventory) {
                $classification = Get-HVVMNameClassification -ShortVMName $request.Name -ExistingVMName $candidate.Name
                if ($classification) {
                    $hits += [pscustomobject]@{ Node=$n; VM=$candidate; Match=$classification }
                }
            }
        } catch { throw "Preflight failed on '$n' for '$($request.Name)': $($_.Exception.Message)" }
    }
    $uniqueHits = @($hits | Group-Object { $_.VM.Id.ToString() } | ForEach-Object { $_.Group[0] } | Sort-Object @{Expression={$_.VM.Name}}, @{Expression={$_.Node}})
    if ($uniqueHits.Count -eq 0) {
        throw "No VM found for '$($request.Name)' on '$target'. No changes made."
    }
    $candidateRows = @($uniqueHits | ForEach-Object {
        [pscustomobject]@{ Id=[string]$_.VM.Id; Name=[string]$_.VM.Name; Node=[string]$_.Node; Kind=[string]$_.Match; State=$_.VM.State; Original=$_ }
    })
    # Preserve adjacency of skip warnings and the preceding AD ambiguity warning.
    $isOverlappingEntry = @($candidateRows | Where-Object {
        $selectionContext.Selected.ContainsKey([string]$_.Id) -or
        $selectionContext.Excluded.ContainsKey([string]$_.Id)
    }).Count -gt 0
    if (-not $isOverlappingEntry -and $pendingADWarnings.Count -gt 0) { & $flushADWarnings }
    $selection = Resolve-HVBatchSelection -RequestedName $request.Name -Candidates $candidateRows `
        -PermittedSelection Multiple -SelectionContext $selectionContext `
        -ValidateOnly:$ValidateOnly -ConfirmSelection -CancelEntireBatch `
        -InputNames @($removalRequests | Where-Object { $_.Host -ieq $request.Host } | ForEach-Object { [string]$_.Name })
    if ($selection.Status -eq 'Skipped') {
        # This message follows the resolver's INCLUDED/EXCLUDED skip warning.
        if ($pendingADWarnings.Count -gt 0) { & $flushADWarnings }
        continue
    }
    if (-not $KeepADAccount -and $candidateRows.Count -gt 1) {
        $adOverride = if ($PSBoundParameters.ContainsKey('ADNameToCleanUp')) { $ADNameToCleanUp } else { $request.ADName }
        $warningADTarget = if (-not [string]::IsNullOrWhiteSpace($adOverride)) {
            $adOverride.Trim().ToUpperInvariant()
        } elseif ([regex]::IsMatch($request.Name, "\A(?:$adShortNamePattern)\z")) {
            $request.Name.Trim().ToUpperInvariant()
        } else { $null }
        # Warn if a selected VM differs from the resolved AD target.
        if ($warningADTarget -and @($selection.Selected | Where-Object { $_.Name -ine $warningADTarget }).Count -gt 0) {
            $pendingADWarnings.Add([pscustomobject]@{
                Target = $warningADTarget
                Names = @($candidateRows | Select-Object -ExpandProperty Name -Unique)
            }) | Out-Null
        }
    }
    foreach ($item in @($selection.Selected)) {
        $chosen = $item.Original
        $vmId = [string]$chosen.VM.Id
        if ($seenIds.ContainsKey($vmId)) { throw "VM GUID '$vmId' selected twice. No removals started." }
        $seenIds[$vmId] = $true
        $preflight.Add([pscustomobject]@{Name=$request.Name;Host=$target;Resolved=$chosen.VM.Name;Node=$chosen.Node;VMId=$vmId;Match=$chosen.Match;Type=$targetType;State=[string]$chosen.VM.State;ADName=$request.ADName}) | Out-Null
    }
}
if ($pendingADWarnings.Count -gt 0) { & $flushADWarnings }
# Build the AD safety plan from selected VM identities before any destructive work.
# A shared AD target or a name mismatch is a warning, not proof of AD ownership.
$adPlans = New-Object 'System.Collections.Generic.List[object]'
foreach ($plannedVM in $preflight) {
    $override = if ($PSBoundParameters.ContainsKey('ADNameToCleanUp')) { $ADNameToCleanUp } else { $plannedVM.ADName }
    $adTarget = if (-not [string]::IsNullOrWhiteSpace($override)) {
        $override.Trim().ToUpperInvariant()
    } elseif ([regex]::IsMatch($plannedVM.Name, "\A(?:$adShortNamePattern)\z")) {
        $plannedVM.Name.Trim().ToUpperInvariant()
    } else { $null }
    if ($adTarget) {
        $adPlans.Add([pscustomobject]@{Target=$adTarget;VM=$plannedVM;Mismatch=($plannedVM.Resolved -ine $adTarget)}) | Out-Null
    }
}
$adActionCompleted = @{}
Write-Host "`n================ VM LIST ================" -ForegroundColor Cyan
$preflight | Format-Table Name,Host,Type,Resolved,Node,State -AutoSize | Out-Host
if ($preflight.Count -eq 0) { throw "No VMs selected for removal. No changes made." }
Write-Host ("All {0} VM(s) identified successfully." -f $preflight.Count) -ForegroundColor Green
# Confirm AD ambiguity only after the complete batch is resolved. This guarantees
# that declining confirmation cancels the whole batch before any VM changes.
if (-not $KeepADAccount) {
    foreach ($adGroup in @($adPlans | Group-Object Target)) {
        $affected = @($adGroup.Group)
        if ($affected.Count -le 1 -and -not $affected[0].Mismatch) { continue }
        $actionName = if ($ResetADAccount) { 'RESET' } else { 'DELETE' }
        if (-not $shownADWarnings.ContainsKey($adGroup.Name)) {
            $names = @($affected | ForEach-Object { $_.VM.Resolved } | Select-Object -Unique)
            Write-Warning ("Resolved AD account '{0}' may be used by any of the following Hyper-V VMs: {1}" -f $adGroup.Name, ($names -join ', '))
            if ($ValidateOnly) { Write-Host "ValidateOnly: $actionName requires explicit confirmation in Apply mode; no changes made." -ForegroundColor Yellow }
        }
        if (-not $ValidateOnly) {
            $adAnswer = Read-Host "Are you sure you want to $actionName AD account '$($adGroup.Name)'? [y/N]"
            if ($adAnswer -cne 'Y' -and $adAnswer -cne 'y') {
                throw "AD action not confirmed for '$($adGroup.Name)'. Entire batch cancelled before changes."
            }
        }
    }
}

if ($ValidateOnly) { Write-Host 'No changes made (ValidateOnly).' -ForegroundColor Green }
else { Write-Host 'Preflight complete. No changes made yet.' -ForegroundColor Green }
if (-not $ValidateOnly -and -not $Y) {
    $batchAnswer = Read-Host "Type Y to authorize removal of ALL $($preflight.Count) listed VM(s) (AD action: $(if($KeepADAccount){'KEEP'}elseif($ResetADAccount){'RESET'}else{'DELETE'}))"
    if ($batchAnswer -cne 'Y' -and $batchAnswer -cne 'y') { Write-Warning 'Batch cancelled. No removal attempted.'; Invoke-HVTiming -Action Report; Stop-Transcript | Out-Null; return }
}
foreach ($request in $preflight) {
    $name = $request.Name
    $TargetHost = $request.Host
    $effective = $TargetHost
    $clusterName = $null
    $nodes = @()
    if (Get-Module -ListAvailable FailoverClusters) {
        try { $clusterName = (Get-Cluster -Name $TargetHost -ErrorAction Stop -WarningAction SilentlyContinue).Name; $nodes = @(Get-ClusterNode -Cluster $clusterName -WarningAction SilentlyContinue | Where-Object State -eq 'Up' | Select-Object -ExpandProperty Name) } catch { $clusterName = $null }
    }
    Write-Host "`n========== $($request.Resolved) ==========" -ForegroundColor Cyan
    if ($request.Resolved -ine $name) { Write-Host "Requested VM : $name" }
    # Recheck selected identity and owning node, not the original short-name pattern.
    # Do not follow migrations after operator confirmation.
    $node = $request.Node
    $vmById = @(Get-VM -ComputerName $node -ErrorAction Stop | Where-Object { [string]$_.Id -eq [string]$request.VMId })
    if ($vmById.Count -ne 1 -or $vmById[0].Name -cne $request.Resolved) {
        throw "Selected VM identity/name changed after preflight for '$name' on '$node'. No deletion attempted."
    }
    $vm = $vmById[0]
    $currentMatch = Get-HVVMNameClassification -ShortVMName $name -ExistingVMName $vm.Name
    if ($currentMatch -ne $request.Match) { throw "Selected VM classification changed after preflight for '$name'. No deletion attempted." }
    if ($clusterName) {
        foreach ($otherNode in @($nodes | Where-Object { $_ -ine $node })) {
            $duplicate = @(Get-VM -ComputerName $otherNode -ErrorAction Stop | Where-Object { [string]$_.Id -eq [string]$request.VMId })
            if ($duplicate.Count) { throw "Selected VM ID appears on another node '$otherNode'; re-run preflight. No deletion attempted." }
        }
    }
    $role = $null
    $vmCluster = $clusterName
    if (-not $vmCluster -and $TargetHost -and (Get-Module -ListAvailable FailoverClusters)) {
        try { $vmCluster = (Get-Cluster -Name $node -ErrorAction Stop -WarningAction SilentlyContinue).Name } catch { }
    }
    if ($vmCluster) { $role = Get-ClusterVMRoleById -Cluster $vmCluster -Id $vm.Id }
    Write-Host "VM: $($vm.Name) | Node: $node | Cluster: $vmCluster"
    $isLocalNode = ($node -ieq $env:COMPUTERNAME -or $node -ieq "$env:COMPUTERNAME.$env:USERDNSDOMAIN" -or $node -ieq 'localhost' -or $node -eq '.')
    $externalAD = $true
    # AD identity is independent of the resolved Hyper-V display name.
    # An explicit per-row ADName (or single-VM CLI override) takes precedence.
    # Otherwise the REQUESTED VM name must match the configured short-name
    # regex in its entirety. Never extract a substring from a display name.
    $explicitADName = if ($PSBoundParameters.ContainsKey('ADNameToCleanUp')) { $ADNameToCleanUp } else { $request.ADName }
    $adComputerName = $null
    if (-not [string]::IsNullOrWhiteSpace($explicitADName)) {
        $adComputerName = $explicitADName.Trim().ToUpperInvariant()
    } elseif ([regex]::IsMatch($name, "\A(?:$adShortNamePattern)\z")) {
        $adComputerName = $name.Trim().ToUpperInvariant()
    } else {
        Write-Warning "Requested VM name '$name' does not match configured VMNaming.ShortNamePattern; AD cleanup will be skipped. Use -ADNameToCleanUp for a single VM or the ADName column in -VMListFile to specify an account."
    }
    if ($externalAD -and $adComputerName) {
        $adStatus = Get-JumpHostADStatus -ComputerName $adComputerName
        $adMode = if ($KeepADAccount) { 'KEEP' } elseif ($ResetADAccount) { 'RESET' } else { 'DELETE' }
        $adSource = if ($explicitADName) { 'Explicit ADName' } else { 'Requested VM name' }
        Write-Host "AD Account   : $adComputerName ($($adStatus.Status)) | Source: $adSource | AD Action: $adMode"
        if ($adStatus.Error) { Write-Warning "AD lookup detail: $($adStatus.Error)" }
    }
    if (-not $adComputerName) { $adStatus = [pscustomobject]@{Status='Skipped';DN=$null;Error='Uncertain AD identity'} }
    # Always validate on target first; original v2.2 validation is read-only.
    Write-Host "`nInspecting VM and storage: $($request.Resolved) on $node (read-only)..." -ForegroundColor Cyan
    Invoke-HVTiming -Action Measure -TimingLabel 'VM and storage inspection total' -Target $node -ScriptBlock { Invoke-RemovalEngine -Node $node -Name $name -ExpectedVMId $request.VMId -ExpectedVMName $request.Resolved -DryRun $true -SkipPrimary $false -ForceFolders $false -RoleHandled $false -ExternalAD $externalAD -EngineCode $engine -InspectionContext $(if ($ValidateOnly) { 'Validation' } else { 'PreRemoval' }) }
    Write-Host 'VM and storage inspection completed.' -ForegroundColor Green
    if ($ValidateOnly) { Write-Host 'No changes made (ValidateOnly).' -ForegroundColor Yellow; continue }
    Write-Host "`n============================================="
    Write-Host $name
    Write-Host "Stage: VM and storage deletion (Apply) | Host: $node" -ForegroundColor Magenta
    Write-Host "============================================="
    # Final identity guard immediately before any destructive cluster-role action.
    $beforeDelete = @(Get-VM -ComputerName $node -ErrorAction Stop | Where-Object { [string]$_.Id -eq [string]$request.VMId })
    if ($beforeDelete.Count -ne 1 -or $beforeDelete[0].Name -cne $request.Resolved) {
        throw "VM changed after inspection; cluster role and VM deletion cancelled for '$name'."
    }
    $handled = $false
    if ($role) {
        Write-Host "Removing cluster role '$role' from $vmCluster (locally on initiating computer)..." -ForegroundColor Yellow
        $g = Get-ClusterGroup -Cluster $vmCluster -Name $role -ErrorAction Stop
        # Remove resources/role but preserve VM, as with v2.2.
        Invoke-HVTiming -Action Measure -TimingLabel 'Remove cluster group' -Target $vmCluster -ScriptBlock { Remove-ClusterGroup -Cluster $vmCluster -Name $role -RemoveResources -Force -ErrorAction Stop }
        Start-Sleep -Seconds 3
        $still = Get-ClusterVMRoleById -Cluster $vmCluster -Id $vm.Id
        if ($still) { throw "Cluster role still exists ($still). VM and disks will NOT be deleted." }
        $handled = $true
        Write-Host 'Cluster role removal verified.' -ForegroundColor Green
    }
    # Embedded engine performs extra-file confirmation unless -ForceFolderCleanup.
    Write-Host "`nDeleting VM and storage: $name on $node..." -ForegroundColor Cyan
    $nodeOutputs = @(Invoke-HVTiming -Action Measure -TimingLabel 'VM and storage removal total' -Target $node -ScriptBlock { Invoke-RemovalEngine -Node $node -Name $name -ExpectedVMId $request.VMId -ExpectedVMName $request.Resolved -DryRun $false -SkipPrimary $true -ForceFolders ([bool]$ForceFolderCleanup) -RoleHandled $handled -ExternalAD $externalAD -EngineCode $engine })
    Write-Host 'VM and storage deletion stage completed; verifying results...' -ForegroundColor Cyan
    $nodeReport = @($nodeOutputs | Where-Object { $_.ResultMarker -eq 'HyperVRemoval.NodeResult.v3.3' } | Select-Object -Last 1)
    if ($nodeReport.Count -gt 0) { $nodeReport = $nodeReport[0] } else { $nodeReport = $null }
    foreach ($otherOutput in @($nodeOutputs | Where-Object { $_.ResultMarker -ne 'HyperVRemoval.NodeResult.v3.3' })) { Write-Output $otherOutput }
    if ($externalAD) {
        # Only remove AD after the VM itself is verified absent on the target node.
        $remaining = @(Get-VM -ComputerName $node -ErrorAction Stop | Where-Object { $_.Id -eq $vm.Id })
        if ($remaining.Count -gt 0) {
            Write-Warning "VM still exists on $node; JumpHost AD cleanup skipped for $adComputerName."
        } else {
            # AD identity must have been derived uniquely; no additional confirmation prompt.
            if (-not $adComputerName) {
                Write-Warning 'AD cleanup skipped: no explicit AD name and requested VM name does not match configured short-name pattern.'
            } elseif ($KeepADAccount) {
                Write-Host "AD computer '$adComputerName' preserved unchanged (-KeepADAccount)." -ForegroundColor Green
            } elseif ($adActionCompleted.ContainsKey($adComputerName)) {
                Write-Host "AD cleanup skipped: '$adComputerName' already processed by an earlier selected VM." -ForegroundColor Yellow
            } else {
                Invoke-HVTiming -Action Measure -TimingLabel 'AD cleanup' -Target $adComputerName -ScriptBlock { Remove-JumpHostADComputer -ComputerName $adComputerName -Status $adStatus -ResetAccount ([bool]$ResetADAccount) }
                $adActionCompleted[$adComputerName] = $true
            }
        }
    }
    # Consolidated outcome from actual node-level removal report and read-only verification.
    Write-Host "`n================ FINAL REPORT ================" -ForegroundColor Cyan
    Write-Host ""
    $issues = New-Object 'System.Collections.Generic.List[string]'
    if ($role) {
        $roleRemaining = Get-ClusterVMRoleById -Cluster $vmCluster -Id $vm.Id
        if (-not $roleRemaining) {
            Write-Host "Cluster role : REMOVED and verified | $role | $vmCluster" -ForegroundColor Green
        } else {
            $issues.Add("Cluster role still present: $roleRemaining")
            Write-Warning "Cluster role : STILL PRESENT | $roleRemaining | $vmCluster"
        }
    } else { Write-Host 'Cluster role : None registered' }
    $vmRemaining = @(Get-VM -ComputerName $node -ErrorAction Stop | Where-Object { $_.Id -eq $vm.Id })
    if ($vmRemaining.Count -eq 0) {
        Write-Host "VM           : REMOVED and verified | $($vm.Name) | $node" -ForegroundColor Green
    } else {
        $issues.Add("VM still present on $node")
        Write-Warning "VM           : STILL PRESENT | $($vm.Name) | $node"
    }
    Write-Host ""
    if ($nodeReport) {
        $diskList = @($nodeReport.DirectDisksRemoved | Where-Object { $_ })
        Write-Host ("Disks removed : {0}" -f $diskList.Count)
        foreach ($path in $diskList) { Write-Host "  $path" }
        Write-Host ""
        $sidecars = @($nodeReport.SidecarFilesRemoved | Where-Object { $_ })
        Write-Host ("Additional disk-related files : {0} removed" -f $sidecars.Count)
        $extra = @($nodeReport.FolderCandidatesRemoved | Where-Object { $_ })
        Write-Host ("Extra files  : {0} found, {1} removed" -f $nodeReport.ExtraFilesFound, $extra.Count)
        Write-Host ""
        $lockedFiles = @($nodeReport.LockedFiles | Where-Object { $_ })
        Write-Host ("Locked files : {0}" -f $lockedFiles.Count)
        foreach ($lockedFile in $lockedFiles) { Write-Warning "  $lockedFile" }
        Write-Host ""
        $configs = @($nodeReport.VMConfigRuntimeFilesRemoved | Where-Object { $_ })
        $configInventory = @($nodeReport.VMConfigRuntimeFilesInventoried | Where-Object { $_ })
        if ($configs.Count) {
            Write-Host ("Config files : {0} removed" -f $configs.Count)
        } elseif ($configInventory.Count) {
            # Verify disappearance on the node instead of assuming Hyper-V deleted them.
            if ($isLocalNode) {
                $configStillPresent = @($configInventory | Where-Object { Test-Path -LiteralPath $_ })
            } else {
                $configStillPresent = @(Invoke-Command -ComputerName $node -ArgumentList (,$configInventory) -ScriptBlock {
                    param([string[]]$paths)
                    foreach ($path in $paths) { if (Test-Path -LiteralPath $path) { $path } }
                } -ErrorAction Stop)
            }
            if ($configStillPresent.Count) {
                Write-Host 'VM config/runtime files       : Some files remain'
                foreach ($path in $configStillPresent) { $issues.Add("Config/runtime file remains: $path") }
            } else { Write-Host 'VM config/runtime files       : Removed by Hyper-V / cleanup (verified)' }
        } else { Write-Host 'VM config/runtime files       : None inventoried' }
        Write-Host ""
        $folders = @($nodeReport.FoldersRemoved | Where-Object { $_ })
        Write-Host ("Folders removed: {0}" -f $folders.Count)
        foreach ($path in $folders) { Write-Host "  $path" }
        foreach ($warningText in @($nodeReport.Warnings | Where-Object { $_ })) {
            if ($warningText -notmatch '^AD computer .* was not found|^AD module unavailable|^AD cleanup is delegated|^Cluster role removal not required') {
                $issues.Add([string]$warningText)
            }
        }
    } else {
        $issues.Add('Node-level removal report unavailable; disk and folder outcomes cannot be confirmed')
        Write-Host 'Disk/file/folder results     : Unavailable'
    }
    Write-Host ""
    if ($externalAD) {
        if ($KeepADAccount) {
            if ($adStatus.Status -eq 'Found') {
                $adAfter = Get-JumpHostADStatus -ComputerName $adComputerName
                if ($adAfter.Status -eq 'Found' -and $adAfter.DN -eq $adStatus.DN) {
                    Write-Host "AD computer  : PRESERVED (unchanged by command) | $adComputerName" -ForegroundColor Green
                } else {
                    $issues.Add("AD preservation verification inconclusive: $($adAfter.Status) $($adAfter.Error)")
                    Write-Warning "AD computer  : Preservation not verified | $adComputerName"
                }
            } elseif ($adStatus.Status -eq 'NotFound') {
                Write-Host "AD computer  : NOT FOUND | $adComputerName | No AD changes attempted"
            } elseif ($adStatus.Status -eq 'Skipped') {
                Write-Host 'AD computer  : SKIPPED (identity not certain); no AD changes attempted' -ForegroundColor Yellow
            } else {
                Write-Host "AD computer  : $($adStatus.Status) | $adComputerName | No AD changes attempted" -ForegroundColor Yellow
            }
        } elseif ($adStatus.Status -eq 'Skipped') {
            Write-Host 'AD computer  : SKIPPED (identity not certain)' -ForegroundColor Yellow
        } elseif ($adStatus.Status -eq 'NotFound') {
            Write-Host "AD computer  : NOT FOUND | $adComputerName | No deletion required"
        } elseif ($adStatus.Status -eq 'Found') {
            $adAfter = Get-JumpHostADStatus -ComputerName $adComputerName
            if (($ResetADAccount -and $adAfter.Status -eq 'Found') -or (-not $ResetADAccount -and $adAfter.Status -eq 'NotFound')) {
                Write-Host "AD computer  : $(if($ResetADAccount){'PRESERVED after password reset'}else{'ABSENT after cleanup'}) | $adComputerName" -ForegroundColor Green
            } else {
                $issues.Add("AD cleanup not verified: $($adAfter.Status) $($adAfter.Error)")
                Write-Warning "AD computer  : $($adAfter.Status) | $adComputerName"
            }
        } else { $issues.Add("AD check: $($adStatus.Status) $($adStatus.Error)"); Write-Host "AD computer  : $($adStatus.Status) | $adComputerName" }
    } elseif ($nodeReport) {
        $removedAD = @($nodeReport.ADRemoved | Where-Object { $_ })
        if ($removedAD.Count) { Write-Host "AD computer  : REMOVED | $($removedAD -join ', ')" }
        else { Write-Host 'AD computer  : See local AD result above' }
    }
    Write-Host ""
    if ($issues.Count) {
        Write-Host 'Warnings:' -ForegroundColor Yellow
        foreach ($issue in $issues) { Write-Host " - $issue" -ForegroundColor Yellow }
        Write-Host ""
        Write-Host 'Operation completed with warnings / incomplete verification.' -ForegroundColor Yellow
    } else {
        Write-Host 'Warnings     : None'
        Write-Host ""
        Write-Host 'Operation completed successfully.' -ForegroundColor Green
    }
    Write-Host '====================================================='

}

} catch {
    Write-Host ("ERROR: {0}" -f $_.Exception.Message) -ForegroundColor Red
    Write-Host 'Operation stopped. Review the log for details.' -ForegroundColor Yellow
} finally {
    try { Invoke-HVTiming -Action Report } catch { Write-Warning "Timing summary failed: $($_.Exception.Message)" }
    try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
}

}
