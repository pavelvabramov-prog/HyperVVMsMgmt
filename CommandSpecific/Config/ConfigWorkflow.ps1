# Purpose: Wait-VMRunning - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Step 9.3 Phase 2: module-shipped shared helpers are loaded in the
# current engine script scope, on both the jump host and the Hyper-V node.
$hvConfigSharedPath = Join-Path $PSScriptRoot 'HVConfigShared.ps1'
if (-not (Test-Path -LiteralPath $hvConfigSharedPath -PathType Leaf)) {
    throw "hv-config shared helper payload missing: $hvConfigSharedPath"
}
. $hvConfigSharedPath


if ($Help -or ($args -contains '/?') -or $ConfigFile -in @('/?','?','-?','--help','help')) {
    Show-UsageHelp
    return
}

if ([string]::IsNullOrWhiteSpace($ConfigFile)) { throw 'Invalid or missing parameter: specify -ConfigFile. Use hv-config -Help for help.' }

$currentIdentity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)

if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "This script must be run from an elevated PowerShell session (Run as Administrator)."
}

$Script:TranscriptStarted = $false
$Script:LogFilePath = $null

# ------------------------------------------------------------
# Utility functions
# ------------------------------------------------------------


# Config-compatible adapter; formatting is implemented in canonical Shared/Get-HVDisplayVMName.


# Config-compatible adapter; validation is implemented in canonical Shared/Test-HVShortVMName.


# ------------------------------------------------------------
# Parse config
# ------------------------------------------------------------


# ------------------------------------------------------------
# Force-refresh scriptblock variables
# ------------------------------------------------------------

Remove-Variable sbWaitGuestHeartbeatOnly -ErrorAction SilentlyContinue
Remove-Variable sbGuestReady -ErrorAction SilentlyContinue
Remove-Variable sbHostAdapterPrecheck -ErrorAction SilentlyContinue
Remove-Variable sbGuestAdapterPrecheck -ErrorAction SilentlyContinue
Remove-Variable sbGetGuestAdapterSnapshot -ErrorAction SilentlyContinue
Remove-Variable sbMapGuestAdaptersByDisconnect -ErrorAction SilentlyContinue
Remove-Variable sbPrepareStandaloneAndRename -ErrorAction SilentlyContinue
Remove-Variable sbReconnectVmNetworkAdapters -ErrorAction SilentlyContinue
Remove-Variable sbDisconnectAllVmNetworkAdapters -ErrorAction SilentlyContinue
Remove-Variable sbReconnectPrimaryVmNetworkAdapterOnly -ErrorAction SilentlyContinue
Remove-Variable sbSetPrimaryNicOnlyConnected -ErrorAction SilentlyContinue
Remove-Variable sbRestoreVmNetworkAdapterStates -ErrorAction SilentlyContinue
Remove-Variable sbApplyGuestNetworkAndLocalConfig -ErrorAction SilentlyContinue
Remove-Variable sbJoinDomain -ErrorAction SilentlyContinue
Remove-Variable sbAddDomainUsersToLocalAdmins -ErrorAction SilentlyContinue

# ------------------------------------------------------------
# Local script blocks
# ------------------------------------------------------------

$sbWaitGuestHeartbeatOnly = {
    param($VMName)

    Import-Module Hyper-V -ErrorAction Stop

    # Waits for vMRunning for the calling workflow.
    function Wait-VMRunning {
        param(
            [string]$VMName,
            [int]$TimeoutSec = 180
        )

        $elapsed = 0
        while ((Get-VM -Name $VMName).State -ne "Running") {
            Start-Sleep -Seconds 3
            $elapsed += 3

            if ($elapsed -ge $TimeoutSec) {
                throw "VM '$VMName' did not reach Running state within $TimeoutSec seconds."
            }
        }
    }

    # Waits for vMHeartbeat Ready for the calling workflow.
    function Wait-VMHeartbeatReady {
        param(
            [string]$VMName,
            [int]$TimeoutSec = 300
        )

        Write-Host "INFO: Waiting for guest heartbeat..." -ForegroundColor Cyan

        $heartbeatReady = $false
        $heartbeatNote = ""
        $elapsedHeartbeat = 0

        while ($elapsedHeartbeat -lt $TimeoutSec) {
            $hb = Get-VMIntegrationService -VMName $VMName -Name 'Heartbeat' -ErrorAction SilentlyContinue

            if ($hb) {
                $heartbeatText = @(
                    $hb.PrimaryStatusDescription
                    $hb.SecondaryStatusDescription
                ) -join ' | '

                $heartbeatNote = $heartbeatText

                if ($heartbeatText -match 'Operating normally' -or $heartbeatText -match 'OK') {
                    $heartbeatReady = $true
                    break
                }
            }

            Start-Sleep -Seconds 5
            $elapsedHeartbeat += 5
        }

        if (-not $heartbeatReady) {
            throw "VM '$VMName' heartbeat did not become ready within $TimeoutSec seconds. Last heartbeat status: $heartbeatNote"
        }

        Write-Host "INFO: Guest heartbeat is ready." -ForegroundColor Green
    }

    $vm = Get-VM -Name $VMName -ErrorAction Stop

    if ($vm.State -eq "Off") {
        Start-VM -Name $VMName | Out-Null
    }
    elseif ($vm.State -eq "Paused") {
        Resume-VM -Name $VMName | Out-Null
    }

    Wait-VMRunning -VMName $VMName
    Wait-VMHeartbeatReady -VMName $VMName

    [pscustomobject]@{
        Ready = $true
    }
}

$sbGuestReady = {
    param($VMName, $cred)

    & $sbWaitGuestHeartbeatOnly $VMName | Out-Null

    # Checks power Shell Direct Connection for the calling workflow.
    function Test-PowerShellDirectConnection {
        param(
            [string]$VMName,
            [pscredential]$Credential,
            [int]$InitialDelaySec = 30,
            [int]$Attempts = 20,
            [int]$DelayBetweenAttemptsSec = 10
        )

        Write-Host "INFO: Waiting extra time for first-boot guest logon services..." -ForegroundColor Cyan
        Start-Sleep -Seconds $InitialDelaySec

        Write-Host "INFO: Testing PowerShell Direct credentials..." -ForegroundColor Cyan

        $connected = $false
        $lastReason = 'PowerShell Direct connection unavailable'
        $lastCategory = 'GUESTNOTREADY'

        for ($i = 1; $i -le $Attempts; $i++) {
            # VM may restart between the heartbeat check and PowerShell Direct.
            $vmState = $null
            try {
                $vmState = (Get-VM -Name $VMName -ErrorAction Stop).State
            }
            catch {
                $lastCategory = 'VMSTATEFAIL'
                $lastReason = 'Unable to query the VM state'
            }

            if ($null -ne $vmState -and $vmState -ne 'Running') {
                $lastCategory = 'VMNOTRUNNING'
                $lastReason = "VM state is $vmState"
            }
            elseif ($null -ne $vmState) {
                try {
                    Invoke-Command -VMName $VMName -Credential $Credential -ScriptBlock { 'ok' } -ErrorAction Stop | Out-Null
                    $connected = $true
                    break
                }
                catch {
                    $errorId = [string]$_.FullyQualifiedErrorId
                    $errorMessage = [string]$_.Exception.Message
                    if ($errorId -match 'InvalidVMState' -or $errorMessage -match 'not in running state') {
                        $lastCategory = 'VMNOTRUNNING'
                        $lastReason = 'VM changed state during the connection attempt'
                    }
                    elseif ($errorMessage -match 'credential is invalid|logon failure|user name or password is incorrect|access is denied') {
                        $lastCategory = 'GUESTAUTHWAIT'
                        $lastReason = 'Guest rejected the credentials (may still be initializing)'
                    }
                    else {
                        $lastCategory = 'GUESTNOTREADY'
                        $lastReason = 'PowerShell Direct connection unavailable'
                    }
                }
            }

            if ($i -lt $Attempts) {
                Write-Host "INFO: PowerShell Direct not ready ($i/$Attempts): $lastReason; retrying in $DelayBetweenAttemptsSec seconds..." -ForegroundColor Yellow
                Start-Sleep -Seconds $DelayBetweenAttemptsSec
            }
        }

        if (-not $connected) {
            throw "GUESTREADYTIMEOUT: VM '$VMName' is not ready for PowerShell Direct after $Attempts attempt(s). Last status: $lastReason. Verify VM is running and Windows has finished starting; if it is ready, verify guest credentials."
        }

        Write-Host "INFO: Credentials OK." -ForegroundColor Green
    }

    Test-PowerShellDirectConnection -VMName $VMName -Credential $cred -Attempts $PSDirectMaxAttempts

    [pscustomobject]@{
        Ready = $true
    }
}

$sbHostAdapterPrecheck = {
    param($VMName, $nics)

    Import-Module Hyper-V -ErrorAction Stop

    $allAdapters = Get-VMNetworkAdapter -VMName $VMName -ErrorAction Stop
    $adapterMap = @()

    foreach ($nic in @($nics)) {
        if ([string]::IsNullOrWhiteSpace($nic.Name)) {
            continue
        }

        $hv = $allAdapters | Where-Object {
            $_.Name.Trim().ToLower() -eq $nic.Name.Trim().ToLower()
        } | Select-Object -First 1

        if (-not $hv) {
            $hasConfig =
                (-not [string]::IsNullOrWhiteSpace($nic.IP)) -or
                (-not [string]::IsNullOrWhiteSpace($nic.Gateway)) -or
                ($nic.DNS -and $nic.DNS.Count -gt 0)

            if ($hasConfig) {
                $available = $allAdapters.Name -join ", "
                throw "Hyper-V adapter '$($nic.Name)' was not found on VM '$VMName', but configuration for it exists. Available adapters: $available"
            }
            else {
                Write-Warning "VM '$VMName': adapter '$($nic.Name)' not present on VM and has no configuration  -  skipping."
                continue
            }
        }

        $adapterMap += [pscustomobject]@{
            Name               = $nic.Name
            IP                 = $nic.IP
            Prefix             = $nic.Prefix
            Mask               = $nic.Mask
            GW                 = $nic.Gateway
            DNS                = $nic.DNS
            SwitchName         = $hv.SwitchName
            OriginalSwitchName = $hv.SwitchName
            OriginallyConnected = (-not [string]::IsNullOrWhiteSpace($hv.SwitchName))
            GuestMac           = $null
            GuestAlias         = $null
            GuestIfIndex       = $null
        }
    }

    [pscustomobject]@{
        AdapterMap = @($adapterMap)
    }
}

$sbGuestAdapterPrecheck = {
    param($VMName, $cred, $ComputerName)

    $guestPrecheck = Invoke-Command -VMName $VMName -Credential $cred -ArgumentList $ComputerName -ScriptBlock {
        param($ComputerName)

        # Handles mac for the calling workflow.
        function Normalize-Mac {
            param([string]$m)

            if ([string]::IsNullOrWhiteSpace($m)) { return "" }
            return (($m -replace '[^A-Fa-f0-9]', '').ToUpper())
        }

        $all = @(Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue)
        $real = @($all | Where-Object {
            $mac = Normalize-Mac $_.MacAddress
            (-not [string]::IsNullOrWhiteSpace($mac)) -and
            ($_.HardwareInterface -eq $true) -and
            ($_.Status -ne 'Not Present')
        })

        $cs = Get-CimInstance Win32_ComputerSystem

        [pscustomobject]@{
            Success             = $true
            RenameRequired      = ($env:COMPUTERNAME -ne $ComputerName)
            CurrentComputerName = $env:COMPUTERNAME
            PartOfDomain        = [bool]$cs.PartOfDomain
            CurrentDomain       = [string]$cs.Domain
            RealGuestAdapterCount = $real.Count
            RealGuestAdapters = @($real | ForEach-Object {
                [pscustomobject]@{
                    Name      = $_.Name
                    IfIndex   = $_.ifIndex
                    Mac       = Normalize-Mac $_.MacAddress
                    Status    = $_.Status
                }
            })
        }
    } -ErrorAction Stop

    return $guestPrecheck
}

$sbGetGuestAdapterSnapshot = {
    param($VMName, $cred)

    return Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
        # Handles mac for the calling workflow.
        function Normalize-Mac {
            param([string]$m)

            if ([string]::IsNullOrWhiteSpace($m)) { return "" }
            return (($m -replace '[^A-Fa-f0-9]', '').ToUpper())
        }

        $all = @(Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue)

        @($all | Where-Object {
            $mac = Normalize-Mac $_.MacAddress
            (-not [string]::IsNullOrWhiteSpace($mac)) -and
            ($_.HardwareInterface -eq $true) -and
            ($_.Status -ne 'Not Present')
        } | ForEach-Object {
            [pscustomobject]@{
                Name      = $_.Name
                IfIndex   = [uint32]$_.ifIndex
                Mac       = Normalize-Mac $_.MacAddress
                Status    = [string]$_.Status
                LinkSpeed = [string]$_.LinkSpeed
            }
        })
    } -ErrorAction Stop
}

$sbMapGuestAdaptersByDisconnect = {
    param($VMName, $cred, $adapterMap)

    Import-Module Hyper-V -ErrorAction Stop

    # Retrieves snapshot By Mac for the calling workflow.
    function Get-SnapshotByMac {
        param([object[]]$Snapshot, [string]$Mac)

        return @($Snapshot | Where-Object { $_.Mac -eq $Mac } | Select-Object -First 1)
    }

    # Retrieves temporary Mapping Switch Name for the calling workflow.
    function Get-TemporaryMappingSwitchName {
        param([string]$VMName)

        $currentVmAdapters = @(Get-VMNetworkAdapter -VMName $VMName -ErrorAction Stop)

        $preferred = $currentVmAdapters | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_.SwitchName)
        } | Select-Object -First 1

        if ($preferred) {
            return [string]$preferred.SwitchName
        }

        $allSwitches = @(Get-VMSwitch -ErrorAction Stop)
        $fallback = $allSwitches | Select-Object -First 1
        if ($fallback) {
            return [string]$fallback.Name
        }

        throw "No Hyper-V vSwitch is available for temporary NIC mapping on VM '$VMName'."
    }

    $adapterMapList = @($adapterMap)

    $beforeAll = & $sbGetGuestAdapterSnapshot $VMName $cred
    $realGuestAll = @($beforeAll)

    if ($adapterMapList.Count -eq 1 -and $realGuestAll.Count -eq 1) {
        Write-Host "INFO: Single configured NIC and single real guest NIC detected. Using direct safe mapping." -ForegroundColor Cyan

        $adapterMapList[0].GuestMac = $realGuestAll[0].Mac
        $adapterMapList[0].GuestAlias = $realGuestAll[0].Name
        $adapterMapList[0].GuestIfIndex = $realGuestAll[0].IfIndex

        return [pscustomobject]@{
            Success    = $true
            AdapterMap = @($adapterMapList)
        }
    }

    foreach ($nic in $adapterMapList) {
        $before = & $sbGetGuestAdapterSnapshot $VMName $cred
        $wasConnected = (-not [string]::IsNullOrWhiteSpace($nic.SwitchName))
        $temporarySwitchName = $null

        if ($wasConnected) {
            Write-Host "INFO: Identifying guest adapter for Hyper-V NIC '$($nic.Name)' by temporary disconnect/reconnect..." -ForegroundColor Cyan
            Disconnect-VMNetworkAdapter -VMName $VMName -Name $nic.Name -ErrorAction Stop
        }
        else {
            $temporarySwitchName = Get-TemporaryMappingSwitchName -VMName $VMName
            Write-Host "INFO: Identifying guest adapter for Hyper-V NIC '$($nic.Name)' by temporary connect/disconnect using vSwitch '$temporarySwitchName'..." -ForegroundColor Cyan
            Connect-VMNetworkAdapter -VMName $VMName -Name $nic.Name -SwitchName $temporarySwitchName -ErrorAction Stop
        }

        Start-Sleep -Seconds 6

        try {
            $after = & $sbGetGuestAdapterSnapshot $VMName $cred
        }
        finally {
            if ($wasConnected) {
                Connect-VMNetworkAdapter -VMName $VMName -Name $nic.Name -SwitchName $nic.SwitchName -ErrorAction Stop
            }
            else {
                Disconnect-VMNetworkAdapter -VMName $VMName -Name $nic.Name -ErrorAction Stop
            }
            Start-Sleep -Seconds 6
        }

        $changes = @()

        foreach ($b in $before) {
            $a = $after | Where-Object { $_.Mac -eq $b.Mac } | Select-Object -First 1
            if (-not $a) {
                $changes += $b
                continue
            }

            if ($b.Status -ne $a.Status -or $b.LinkSpeed -ne $a.LinkSpeed) {
                $changes += $a
            }
        }

        $afterOnly = @($after | Where-Object {
            $mac = $_.Mac
            -not ($before | Where-Object { $_.Mac -eq $mac } | Select-Object -First 1)
        })
        if ($afterOnly.Count -gt 0) {
            $changes += $afterOnly
        }

        $changes = @($changes | Group-Object Mac | ForEach-Object { $_.Group[0] })

        if ($changes.Count -eq 1) {
            $nic.GuestMac = $changes[0].Mac
            $nic.GuestAlias = $changes[0].Name
            $nic.GuestIfIndex = $changes[0].IfIndex

            Write-Host "INFO: Hyper-V NIC '$($nic.Name)' mapped to guest adapter '$($nic.GuestAlias)' [MAC=$($nic.GuestMac)]" -ForegroundColor Green
        }
        else {
            $details = if ($changes.Count -gt 0) {
                $changes | ForEach-Object { "$($_.Name) [MAC=$($_.Mac), Status=$($_.Status), Link=$($_.LinkSpeed)]" } | Join-String -Separator "; "
            }
            else {
                "(no unique guest adapter change detected)"
            }

            throw "Could not uniquely map Hyper-V NIC '$($nic.Name)' to a guest adapter by state toggle. Observed changes: $details"
        }
    }

    return [pscustomobject]@{
        Success    = $true
        AdapterMap = @($adapterMapList)
    }
}

$sbPrepareStandaloneAndRename = {
    param($VMName, $cred, $ComputerName, $GuestUser, $GuestPass, $adapterMap)

    $guestState = Invoke-Command -VMName $VMName -Credential $cred -ArgumentList $ComputerName -ScriptBlock {
        param($ComputerName)

        $cs = Get-WmiObject Win32_ComputerSystem -ErrorAction Stop

        [pscustomobject]@{
            PartOfDomain   = [bool]$cs.PartOfDomain
            CurrentDomain  = [string]$cs.Domain
            RenameRequired = ($env:COMPUTERNAME -ne $ComputerName)
            CurrentName    = $env:COMPUTERNAME
        }
    } -ErrorAction Stop

    $renameRequired = [bool]$guestState.RenameRequired
    $workgroupChangeRequired = [bool]$guestState.PartOfDomain
    $offlineChangeRequired = ($renameRequired -or $workgroupChangeRequired)

    if (-not $offlineChangeRequired) {
        Write-Host "Guest is already in a workgroup or standalone state." -ForegroundColor Cyan
        Write-Host "Computer name is already '$ComputerName'." -ForegroundColor Cyan

        return [pscustomobject]@{
            RenameRequired          = $false
            WorkgroupChangeRequired = $false
            RestartRequired         = $false
            AdaptersDisconnected    = $false
        }
    }

    $result = Invoke-Command -VMName $VMName -Credential $cred -ArgumentList $ComputerName,$GuestUser,$GuestPass -ScriptBlock {
        param($ComputerName,$GuestUser,$GuestPass)

        $cs = Get-WmiObject Win32_ComputerSystem -ErrorAction Stop

        $renameRequired = ($env:COMPUTERNAME -ne $ComputerName)
        $workgroupChangeRequired = [bool]$cs.PartOfDomain

        if ($workgroupChangeRequired) {
            Write-Host "Guest is currently domain-joined to '$($cs.Domain)'. Switching to WORKGROUP..." -ForegroundColor Yellow

            try {
                $localCred = New-Object System.Management.Automation.PSCredential (
                    $GuestUser,
                    (ConvertTo-SecureString $GuestPass -AsPlainText -Force)
                )

                Remove-Computer `
                    -WorkgroupName "WORKGROUP" `
                    -Credential $localCred `
                    -Force `
                    -ErrorAction Stop
            }
            catch {
                throw "Failed removing computer from domain '$($cs.Domain)'. $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Guest is already in a workgroup or standalone state." -ForegroundColor Cyan
        }

        if ($renameRequired) {
            Write-Host "Renaming computer from '$env:COMPUTERNAME' to '$ComputerName'..." -ForegroundColor Yellow
            Rename-Computer -NewName $ComputerName -Force -ErrorAction Stop
        }
        else {
            Write-Host "Computer name is already '$ComputerName'." -ForegroundColor Cyan
        }

        [pscustomobject]@{
            RenameRequired          = $renameRequired
            WorkgroupChangeRequired = $workgroupChangeRequired
            RestartRequired         = ($renameRequired -or $workgroupChangeRequired)
        }
    } -ErrorAction Stop

    if ($result.RestartRequired) {
        Write-Host "Restarting guest after standalone/rename step..." -ForegroundColor Yellow
        Restart-VM -Name $VMName -Force -ErrorAction Stop
    }

    [pscustomobject]@{
        RenameRequired          = [bool]$result.RenameRequired
        WorkgroupChangeRequired = [bool]$result.WorkgroupChangeRequired
        RestartRequired         = [bool]$result.RestartRequired
        AdaptersDisconnected    = $false
    }
}

$sbReconnectVmNetworkAdapters = {
    param($VMName, $adapterMap)

    & $sbRestoreVmNetworkAdapterStates $VMName $adapterMap
}

$sbDisconnectAllVmNetworkAdapters = {
    param($VMName)

    Import-Module Hyper-V -ErrorAction Stop

    $allAdapters = @(Get-VMNetworkAdapter -VMName $VMName -ErrorAction Stop)
    if ($allAdapters.Count -lt 1) {
        throw "No VM adapters were found on VM '$VMName'."
    }

    $snapshot = foreach ($adapter in $allAdapters) {
        [pscustomobject]@{
            Name                = $adapter.Name
            OriginalSwitchName  = $adapter.SwitchName
            OriginallyConnected = (-not [string]::IsNullOrWhiteSpace($adapter.SwitchName))
        }
    }

    Write-Host "Applying full VM network isolation before standalone/rename step..." -ForegroundColor Cyan

    foreach ($adapter in $allAdapters) {
        if ([string]::IsNullOrWhiteSpace($adapter.SwitchName)) {
            Write-Host "VM adapter '$($adapter.Name)' is already disconnected." -ForegroundColor Cyan
            continue
        }

        $currentSwitch = [string]$adapter.SwitchName
        Disconnect-VMNetworkAdapter -VMName $VMName -Name $adapter.Name -ErrorAction Stop
        Write-Host "Disconnected VM adapter '$($adapter.Name)' from vSwitch '$currentSwitch'." -ForegroundColor Cyan
    }

    [pscustomobject]@{
        Success        = $true
        AdapterStates  = @($snapshot)
    }
}

$sbReconnectPrimaryVmNetworkAdapterOnly = {
    param($VMName, $adapterMap, $AllVmAdapterStates, $PrimaryNicName)

    Import-Module Hyper-V -ErrorAction Stop

    $adapterMapList = @($adapterMap)
    if ($adapterMapList.Count -eq 0) {
        throw "No configured VM adapters are available to isolate for primary NIC handling."
    }

    $savedStates = @($AllVmAdapterStates)
    if ($savedStates.Count -eq 0) {
        throw "No saved VM adapter state is available for primary NIC reconnect handling on '$VMName'."
    }

    $effectivePrimary = $PrimaryNicName
    if ([string]::IsNullOrWhiteSpace($effectivePrimary)) {
        if ($adapterMapList.Count -eq 1) {
            $effectivePrimary = $adapterMapList[0].Name
        }
        else {
            throw "Mandatory field 'PrimaryNIC(DNSreg)' is missing for multi-NIC VM '$VMName'."
        }
    }

    $primaryMap = @($adapterMapList | Where-Object { $_.Name.Trim().ToLower() -eq $effectivePrimary.Trim().ToLower() } | Select-Object -First 1)
    if ($primaryMap.Count -ne 1) {
        throw "PrimaryNIC(DNSreg) '$effectivePrimary' was not found among configured VM adapters on '$VMName'."
    }

    $primary = $primaryMap[0]
    if ([string]::IsNullOrWhiteSpace($primary.GuestAlias) -and [string]::IsNullOrWhiteSpace($primary.GuestMac)) {
        throw "PrimaryNIC(DNSreg) '$($primary.Name)' on VM '$VMName' was not successfully mapped to a guest NIC."
    }

    $primarySavedState = @($savedStates | Where-Object { $_.Name.Trim().ToLower() -eq $primary.Name.Trim().ToLower() } | Select-Object -First 1)
    if ($primarySavedState.Count -ne 1) {
        $available = $savedStates.Name -join ", "
        throw "PrimaryNIC(DNSreg) '$($primary.Name)' was not found in the saved actual VM adapter state on '$VMName'. Saved adapters: $available"
    }

    if ([string]::IsNullOrWhiteSpace($primarySavedState[0].OriginalSwitchName)) {
        throw "PrimaryNIC(DNSreg) '$($primary.Name)' on VM '$VMName' was not originally connected to any vSwitch, so it cannot be used as the primary network path."
    }

    $allAdapters = @(Get-VMNetworkAdapter -VMName $VMName -ErrorAction Stop)

    Write-Host "Applying PrimaryNIC(DNSreg) connectivity..." -ForegroundColor Cyan

    foreach ($currentAdapter in $allAdapters) {
        $savedState = $savedStates | Where-Object { $_.Name.Trim().ToLower() -eq $currentAdapter.Name.Trim().ToLower() } | Select-Object -First 1
        if (-not $savedState) {
            $savedState = [pscustomobject]@{
                Name = $currentAdapter.Name
                OriginalSwitchName = $currentAdapter.SwitchName
                OriginallyConnected = (-not [string]::IsNullOrWhiteSpace($currentAdapter.SwitchName))
            }
        }

        if ($currentAdapter.Name.Trim().ToLower() -eq $primary.Name.Trim().ToLower()) {
            if ([string]::IsNullOrWhiteSpace($currentAdapter.SwitchName)) {
                Connect-VMNetworkAdapter -VMName $VMName -Name $currentAdapter.Name -SwitchName $primarySavedState[0].OriginalSwitchName -ErrorAction Stop
                Write-Host "Primary VM adapter '$($currentAdapter.Name)' connected to vSwitch '$($primarySavedState[0].OriginalSwitchName)'." -ForegroundColor Cyan
            }
            else {
                Write-Host "Primary VM adapter '$($currentAdapter.Name)' is already connected to vSwitch '$($currentAdapter.SwitchName)'." -ForegroundColor Cyan
            }
            continue
        }

        if ([string]::IsNullOrWhiteSpace($currentAdapter.SwitchName)) {
            Write-Host "Secondary VM adapter '$($currentAdapter.Name)' remains disconnected." -ForegroundColor Cyan
            continue
        }

        $currentSwitch = [string]$currentAdapter.SwitchName
        Disconnect-VMNetworkAdapter -VMName $VMName -Name $currentAdapter.Name -ErrorAction Stop
        Write-Host "Disconnected secondary VM adapter '$($currentAdapter.Name)' from vSwitch '$currentSwitch'." -ForegroundColor Cyan
    }

    [pscustomobject]@{
        PrimaryNicName = $primary.Name
    }
}

$sbSetPrimaryNicOnlyConnected = $sbReconnectPrimaryVmNetworkAdapterOnly

$sbRestoreVmNetworkAdapterStates = {
    param($VMName, $adapterMap)

    Import-Module Hyper-V -ErrorAction Stop

    $allAdapters = @(Get-VMNetworkAdapter -VMName $VMName -ErrorAction Stop)

    foreach ($nic in @($adapterMap)) {
        $currentAdapter = $allAdapters | Where-Object {
            $_.Name.Trim().ToLower() -eq $nic.Name.Trim().ToLower()
        } | Select-Object -First 1

        if (-not $currentAdapter) {
            $available = $allAdapters.Name -join ", "
            throw "VM adapter '$($nic.Name)' was not found on VM '$VMName'. Available adapters: $available"
        }

        if ($nic.OriginallyConnected) {
            if ([string]::IsNullOrWhiteSpace($nic.OriginalSwitchName)) {
                throw "VM adapter '$($nic.Name)' was marked originally connected but has no saved vSwitch name."
            }

            if ([string]::IsNullOrWhiteSpace($currentAdapter.SwitchName)) {
                Connect-VMNetworkAdapter -VMName $VMName -Name $currentAdapter.Name -SwitchName $nic.OriginalSwitchName -ErrorAction Stop
                Write-Host "Reconnected VM adapter '$($currentAdapter.Name)' to vSwitch '$($nic.OriginalSwitchName)'." -ForegroundColor Cyan
            }
            else {
                Write-Host "VM adapter '$($currentAdapter.Name)' is already connected to vSwitch '$($currentAdapter.SwitchName)'." -ForegroundColor Cyan
            }
        }
        else {
            if ([string]::IsNullOrWhiteSpace($currentAdapter.SwitchName)) {
                Write-Host "VM adapter '$($currentAdapter.Name)' remains disconnected." -ForegroundColor Cyan
            }
            else {
                Disconnect-VMNetworkAdapter -VMName $VMName -Name $currentAdapter.Name -ErrorAction Stop
                Write-Host "Restored VM adapter '$($currentAdapter.Name)' to disconnected state." -ForegroundColor Cyan
            }
        }
    }

    [pscustomobject]@{
        Restored = $true
    }
}


$sbTriggerDnsRegistration = {
    param($VMName, $cred)

    Invoke-PsDirectWithRetry `
        -VMName $VMName `
        -Credential $cred `
        -ScriptBlock {
            Write-Host "INFO: Triggering DNS registration..." -ForegroundColor Cyan
            Start-Sleep -Seconds 5
            ipconfig /registerdns | Out-Null
            Write-Host "INFO: DNS registration request sent." -ForegroundColor Green
        } `
        -Attempts 3 `
        -DelaySeconds 5 `
        -StepName "DNS registration trigger" | Out-Null
}

$sbApplyGuestNetworkAndLocalConfig = {
    param($VMName, $cred, $EnableRDP, $NLA, $Firewall, $adapterMap)

    $innerScript = {
        param($EnableRDP,$NLA,$Firewall,$adapterMap)

        # Handles mac for the calling workflow.
        function Normalize-Mac {
            param([string]$m)

            if ([string]::IsNullOrWhiteSpace($m)) { return "" }
            return (($m -replace '[^A-Fa-f0-9]', '').ToUpper())
        }

        # Runs netsh Ipv4 for the calling workflow.
        function Invoke-NetshIpv4 {
    param(
        [string[]]$Arguments,
        [string]$ErrorContext
    )

    $output = & netsh @Arguments 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        $details = if ($output) { ($output | Out-String).Trim() } else { "(no output)" }
        throw "$ErrorContext netsh exit code $exitCode. $details"
    }
}

# Handles interface To Dhcp for the calling workflow.
function Reset-InterfaceToDhcp {
    param([uint32]$IfIndex)

    $adapter = $null
    try {
        $adapter = Get-NetAdapter -InterfaceIndex $IfIndex -ErrorAction Stop
    }
    catch {
        throw "Failed locating adapter for InterfaceIndex $IfIndex. $($_.Exception.Message)"
    }

    $adapterName = [string]$adapter.Name

    $dhcpAddressOk = $false
    $addressOutput = & netsh interface ipv4 set address "name=$adapterName" source=dhcp 2>&1
    $addressExitCode = $LASTEXITCODE
    $addressDetails = if ($addressOutput) { ($addressOutput | Out-String).Trim() } else { "" }

    if ($addressExitCode -eq 0) {
        $dhcpAddressOk = $true
    }
    elseif ($addressDetails -match 'DHCP is already enabled on this interface') {
        Write-Host "INFO: IPv4 DHCP is already enabled on '$adapterName'." -ForegroundColor Cyan
        $dhcpAddressOk = $true
    }

    if (-not $dhcpAddressOk) {
        $details = if ([string]::IsNullOrWhiteSpace($addressDetails)) { "(no output)" } else { $addressDetails }
        throw "Failed enabling IPv4 DHCP on '$adapterName'. netsh exit code $addressExitCode. $details"
    }

    $dnsDhcpOk = $false
    $dnsOutput = & netsh interface ipv4 set dnsservers "name=$adapterName" source=dhcp validate=no 2>&1
    $dnsExitCode = $LASTEXITCODE
    $dnsDetails = if ($dnsOutput) { ($dnsOutput | Out-String).Trim() } else { "" }

    if ($dnsExitCode -eq 0) {
        $dnsDhcpOk = $true
    }
    elseif ($dnsDetails -match 'There are no Domain Name Servers \(DNS\) configured on this computer') {
        $dnsDhcpOk = $true
    }

    if (-not $dnsDhcpOk) {
        $details = if ([string]::IsNullOrWhiteSpace($dnsDetails)) { "(no output)" } else { $dnsDetails }
        throw "Failed resetting DNS to automatic on '$adapterName'. netsh exit code $dnsExitCode. $details"
    }

    $state = Get-NetIPInterface -InterfaceIndex $IfIndex -AddressFamily IPv4 -ErrorAction Stop
    if ($state.Dhcp -ne 'Enabled') {
        throw "IPv4 DHCP is not enabled after reset on '$adapterName'."
    }
}

# Updates interface To Static Ipv4 for the calling workflow.
function Set-InterfaceToStaticIpv4 {
    param(
        [uint32]$IfIndex,
        [string]$IpAddress,
        [string]$SubnetMask,
        [string]$Gateway,
        [string[]]$DnsServers
    )

    $adapter = $null
    try {
        $adapter = Get-NetAdapter -InterfaceIndex $IfIndex -ErrorAction Stop
    }
    catch {
        throw "Failed locating adapter for InterfaceIndex $IfIndex. $($_.Exception.Message)"
    }

    $adapterName = [string]$adapter.Name

    $gatewayArg = if ([string]::IsNullOrWhiteSpace($Gateway)) { 'gateway=none' } else { "gateway=$Gateway" }

    try {
        Invoke-NetshIpv4 `
            -Arguments @('interface','ipv4','set','address',"name=$adapterName",'source=static',"address=$IpAddress","mask=$SubnetMask",$gatewayArg) `
            -ErrorContext "Failed applying static IPv4 address on '$adapterName'."
    }
    catch {
        throw $_.Exception.Message
    }

    if ($DnsServers -and $DnsServers.Count -gt 0) {
        try {
            Invoke-NetshIpv4 `
                -Arguments @('interface','ipv4','set','dnsservers',"name=$adapterName",'source=static',"address=$($DnsServers[0])",'validate=no') `
                -ErrorContext "Failed setting primary DNS server on '$adapterName'."
        }
        catch {
            throw $_.Exception.Message
        }

        if ($DnsServers.Count -gt 1) {
            for ($i = 1; $i -lt $DnsServers.Count; $i++) {
                try {
                    Invoke-NetshIpv4 `
                        -Arguments @('interface','ipv4','add','dnsservers',"name=$adapterName","address=$($DnsServers[$i])","index=$($i+1)",'validate=no') `
                        -ErrorContext "Failed adding DNS server '$($DnsServers[$i])' on '$adapterName'."
                }
                catch {
                    throw $_.Exception.Message
                }
            }
        }
    }
    else {
        try {
            Invoke-NetshIpv4 `
                -Arguments @('interface','ipv4','set','dnsservers',"name=$adapterName",'source=dhcp','validate=no') `
                -ErrorContext "Failed resetting DNS to automatic on '$adapterName'."
        }
        catch {
            throw $_.Exception.Message
        }
    }

    $ipNow = @(Get-NetIPAddress -InterfaceIndex $IfIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -eq $IpAddress })
    if ($ipNow.Count -lt 1) {
        throw "Static IPv4 address '$IpAddress' was not found on '$adapterName' after apply."
    }
}

# Resolves guest Adapter From Stored Mapping for the calling workflow.
function Resolve-GuestAdapterFromStoredMapping {

            param(
                [object[]]$AllAdapters,
                [object]$NicMap
            )

            $guest = $null

            if (-not [string]::IsNullOrWhiteSpace($NicMap.GuestMac)) {
                $guest = $AllAdapters | Where-Object {
                    (Normalize-Mac $_.MacAddress) -eq $NicMap.GuestMac
                } | Select-Object -First 1
            }

            if (-not $guest -and -not [string]::IsNullOrWhiteSpace($NicMap.GuestAlias)) {
                $guest = $AllAdapters | Where-Object {
                    $_.Name.Trim().ToLower() -eq $NicMap.GuestAlias.Trim().ToLower()
                } | Select-Object -First 1
            }

            return $guest
        }

        $adapterMapList = @($adapterMap)
        Start-Sleep -Seconds 10

        $allGuestAdapters = @(Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue)

        foreach ($nic in $adapterMapList) {
            $targetGuest = Resolve-GuestAdapterFromStoredMapping -AllAdapters $allGuestAdapters -NicMap $nic

            if (-not $targetGuest) {
                $available = $allGuestAdapters | ForEach-Object {
                    $name = $_.Name
                    $mac  = Normalize-Mac $_.MacAddress
                    $stat = $_.Status
                    $hw   = $_.HardwareInterface
                    "$name [MAC=$mac, Status=$stat, HW=$hw]"
                }

                $availableText = if ($available.Count -gt 0) { $available -join "; " } else { "(none)" }
                throw "Could not resolve stored guest mapping for Hyper-V NIC '$($nic.Name)'. Expected GuestAlias='$($nic.GuestAlias)', GuestMac='$($nic.GuestMac)'. Guest adapters: $availableText"
            }

            $targetIfIndex = [uint32]$targetGuest.ifIndex

            if (-not [string]::IsNullOrWhiteSpace($nic.IP)) {
                $existingIpMatches = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                    Where-Object { $_.IPAddress -eq $nic.IP })

                if ($existingIpMatches.Count -gt 0) {
                    foreach ($existingIp in $existingIpMatches) {
                        $existingIfIndex = [uint32]$existingIp.InterfaceIndex

                        if ($existingIfIndex -ne $targetIfIndex) {
                            $oldAlias = $null
                            try {
                                $oldAdapter = Get-NetAdapter -InterfaceIndex $existingIfIndex -ErrorAction SilentlyContinue
                                if ($oldAdapter) {
                                    $oldAlias = $oldAdapter.Name
                                }
                            }
                            catch {
                            }

                            if ([string]::IsNullOrWhiteSpace($oldAlias)) {
                                $oldAlias = "InterfaceIndex $existingIfIndex"
                            }

                            Write-Warning "IP '$($nic.IP)' currently exists on '$oldAlias'. Switching that interface to DHCP mode before moving IP to '$($targetGuest.Name)'."

                            try {
                                Reset-InterfaceToDhcp -IfIndex $existingIfIndex
                            }
                            catch {
                                throw "Failed to reset interface '$oldAlias' to DHCP mode. $($_.Exception.Message)"
                            }
                        }
                    }
                }

                try {
                    Set-InterfaceToStaticIpv4 `
                        -IfIndex $targetIfIndex `
                        -IpAddress $nic.IP `
                        -SubnetMask $nic.Mask `
                        -Gateway $nic.GW `
                        -DnsServers $nic.DNS
                }
                catch {
                    throw "Failed applying static IPv4 settings on interface '$($targetGuest.Name)'. $($_.Exception.Message)"
                }
            }
            else {
                Reset-InterfaceToDhcp -IfIndex $targetIfIndex
            }
        }

        if ($EnableRDP -eq $true) {
            Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0
            Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue | Out-Null
        }
        elseif ($EnableRDP -eq $false) {
            Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 1
            Disable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue | Out-Null
        }

        if ($NLA -eq $true) {
            Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication' -Value 1
        }
        elseif ($NLA -eq $false) {
            Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication' -Value 0
        }

        if ($Firewall -eq $false) {
            Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled False | Out-Null
        }
        elseif ($Firewall -eq $true) {
            Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled True | Out-Null
        }

        [pscustomobject]@{
            Applied = $true
        }
    }

    Invoke-PsDirectWithRetry `
        -VMName $VMName `
        -Credential $cred `
        -ScriptBlock $innerScript `
        -ArgumentList @($EnableRDP,$NLA,$Firewall,$adapterMap) `
        -Attempts 8 `
        -DelaySeconds 10 `
        -StepName "Guest network / RDP / firewall apply"
}

$sbJoinDomain = {
    param($VMName, $cred, $Domain, $domainCred, $DomainOU, $ComputerName)

    Invoke-Command -VMName $VMName -Credential $cred -ArgumentList $Domain,$domainCred,$DomainOU -ScriptBlock {
        param($Domain,$domainCred,$DomainOU)

        # v1.69: allow guest network/DNS/DC locator to stabilize before Add-Computer.
        Start-Sleep -Seconds 20

        ipconfig /flushdns | Out-Null
        ipconfig /registerdns | Out-Null

        $dcLocatorOutput = nltest /dsgetdc:$Domain 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "DOMAINCHECKFAIL: nltest /dsgetdc:$Domain failed before domain join. $($dcLocatorOutput -join ' ')"
        }

        $ldapTest = Test-NetConnection -ComputerName $Domain -Port 389 -WarningAction SilentlyContinue
        if (-not $ldapTest.TcpTestSucceeded) {
            throw "DOMAINCHECKFAIL: LDAP TCP/389 test to domain '$Domain' failed before domain join. Resolved target: $($ldapTest.RemoteAddress)"
        }

        Start-Sleep -Seconds 10

        if ([string]::IsNullOrWhiteSpace($DomainOU)) {
            Add-Computer -DomainName $Domain -Credential $domainCred -ErrorAction Stop
        }
        else {
            Add-Computer -DomainName $Domain -Credential $domainCred -OUPath $DomainOU -ErrorAction Stop
        }

        Restart-Computer -Force
    } -ErrorAction Stop

    [pscustomobject]@{
        Joined       = $true
        ComputerName = $ComputerName
    }
}

$sbAddDomainUsersToLocalAdmins = {
    param($VMName, $cred, $UsersToAdd)

    if ($null -eq $UsersToAdd -or @($UsersToAdd).Count -eq 0) {
        return [pscustomobject]@{
            Added   = @()
            Skipped = @()
            Failed  = @()
        }
    }

    Invoke-PsDirectWithRetry `
        -VMName $VMName `
        -Credential $cred `
        -ArgumentList @(, @($UsersToAdd)) `
        -Attempts 6 `
        -DelaySeconds 10 `
        -StepName "Add domain users to local Administrators" `
        -ScriptBlock {
            param($UsersToAdd)

            $groupName = 'Administrators'
            $added = New-Object System.Collections.ArrayList
            $skipped = New-Object System.Collections.ArrayList
            $failed = New-Object System.Collections.ArrayList

            foreach ($userName in @($UsersToAdd)) {
                if ([string]::IsNullOrWhiteSpace($userName)) {
                    continue
                }

                $principal = $userName.Trim()
                if ([string]::IsNullOrWhiteSpace($principal)) {
                    continue
                }

                $alreadyMember = $false
                try {
                    $existingMembers = @(Get-LocalGroupMember -Group $groupName -ErrorAction Stop)
                    $alreadyMember = @($existingMembers | Where-Object {
                        ($_.Name -eq $principal) -or
                        ($_.Name -like "*$principal")
                    }).Count -gt 0
                }
                catch {
                }

                if ($alreadyMember) {
                    [void]$skipped.Add($principal)
                    continue
                }

                try {
                    Add-LocalGroupMember -Group $groupName -Member $principal -ErrorAction Stop
                    [void]$added.Add($principal)
                }
                catch {
                    [void]$failed.Add([pscustomobject]@{
                        User    = $principal
                        Message = $_.Exception.Message
                    })
                }
            }

            [pscustomobject]@{
                Added   = @($added)
                Skipped = @($skipped)
                Failed  = @($failed)
            }
        }
}


# GuestOnly is intentionally disabled until its implementation is validated.
# Reject it before importing modules, reading configuration, or changing any VM.
if ($ADCheckMode -eq "GuestOnly") {
    Write-Host "-ADCheckMode GuestOnly is not supported yet" -ForegroundColor Yellow
    return
}

# ------------------------------------------------------------
# JumpHost dispatcher: original guest configuration engine remains local
# to the owning Hyper-V node, including PowerShell Direct operations.
# ------------------------------------------------------------
if (-not $global:HVGC_ExecutionHost) {
    Import-Module Hyper-V -ErrorAction Stop
    $configFullPath = (Resolve-Path -LiteralPath $ConfigFile -ErrorAction Stop).ProviderPath
    $allSections = @(Get-ConfigSections $configFullPath)
    if ($allSections.Count -eq 0) { throw 'No VM sections found in configuration.' }

    $Script:LaunchComputer = $env:COMPUTERNAME
    $Script:LaunchLogPath = New-ConfigLogFilePath -ConfigFilePath $configFullPath
    $plans = @()
    foreach ($section in $allSections) {
        $baseName = [string]$section.General['VM Name']
        $configuredHost = [string]$section.General['Hyper-V Host']
        if (-not $baseName) { throw 'VM Name is missing from a configuration section.' }
        $requested = $configuredHost.Trim()
        if (-not $requested) { throw "VM '$baseName': Hyper-V Host is missing from configuration." }
        $targetInfo = Get-HVConfigTargetType -Name $requested
        $clusterName = $targetInfo.ClusterName
        $nodes = @($targetInfo.Nodes)
        if ($clusterName) {
            Write-Host "Cluster detected: $clusterName. Online nodes: $($nodes -join ', ')" -ForegroundColor Cyan
        }
        # Discover every candidate before selecting an execution node. A VM may
        # be registered on any online node; always enumerate all ShortNameMatch candidates
        # across every node.
        $hits = @()
        foreach ($node in $nodes) {
            foreach ($vm in @(Get-VM -ComputerName $node -ErrorAction Stop)) {
                $kind = Get-HVVMNameClassification -ShortVMName $baseName -ExistingVMName ([string]$vm.Name)
                if ($null -eq $kind) { continue }
                $hits += [pscustomobject]@{
                    Node = [string]$node; Name = [string]$vm.Name
                    Id = [string]$vm.Id; State = $vm.State; Kind = $kind
                }
            }
        }
        $hits = @($hits | Sort-Object Id -Unique)
        if ($hits.Count -eq 0) {
            Write-Warning "VM '$baseName': found 0 matching VM(s) across target nodes. Skipping (no changes)."
            continue
        }
        $requiresSelection = ($hits.Count -gt 1)
        if ($requiresSelection) {
            Write-Host "Candidate Hyper-V VM objects for '$baseName' across target nodes:" -ForegroundColor Yellow
            $number = 0
            foreach ($hit in $hits) {
                $number++
                Write-Host (" [{0}] {1} | Host={2} | Match={3} | State={4} | Id={5}" -f $number,$hit.Name,$hit.Node,$hit.Kind,$hit.State,$hit.Id) -ForegroundColor Yellow
            }
            # ValidateOnly requires selection but no additional Y/N confirmation.
            # The remote engine still blocks apply actions.
            $selected = Select-VMTargetCandidate -BaseVMName $baseName -Candidates $hits
            if (-not $selected) {
                Write-Warning "VM '$baseName': selection skipped; no changes."
                continue
            }
            if (-not $ValidateOnly) {
                $approved = Confirm-HVSelectedVMMatch -BaseVMName $baseName -CurrentDisplayVMName ("{0} on {1} (VM ID {2})" -f $selected.Name,$selected.Node,$selected.Id)
                if (-not $approved) {
                    Write-Warning "VM '$baseName': selected candidate not confirmed; no changes."
                    continue
                }
            }
        } else {
            $selected = $hits[0]
        }
        $selectedNode = [string]$selected.Node
        Write-Host ("VM '{0}' resolved on '{1}' as '{2}' (VM ID {3})." -f $baseName,$selectedNode,$selected.Name,$selected.Id) -ForegroundColor Cyan
        $plans += [pscustomobject]@{ VMName=$baseName; Node=$selectedNode; Cluster=$clusterName; VMId=[string]$selected.Id }

    }
    if ($plans.Count -eq 0) { Write-Warning 'No VMs selected for processing.'; return }

    # AD prechecks are performed once on the initiating machine, never on Hyper-V nodes.
    # Keep GuestOnly implementation below intact for future troubleshooting.
    $domainCredentialForNodes = Get-SessionDomainCredential
    $jumpHostAdResults = @{}
    $selectedNames = @($plans | ForEach-Object VMName)
    $domainSections = @($allSections | Where-Object {
        $_.General['VM Name'] -in $selectedNames -and
        -not [string]::IsNullOrWhiteSpace([string]$_.General['Domain'])
    })
    if ($domainSections.Count -gt 0) {
        if ($null -eq $domainCredentialForNodes) {
            Write-Host 'Validation FAILED. No VM configuration changes were started.' -ForegroundColor Red
            Write-Host 'Domain credentials are required by the selected VM configuration but $domainCred is not initialized.' -ForegroundColor Yellow
            Write-Host 'Run hv-creds in this PowerShell session, then rerun hv-config.' -ForegroundColor Yellow
            return
        }
        Import-Module ActiveDirectory -ErrorAction Stop
        foreach ($section in $domainSections) {
            $general = $section.General
            $vmName = [string]$general['VM Name']
            $targetName = Get-TargetComputerName -VMName $vmName -PCNameOverride ([string]$general['PCNameOverride'])
            # The AD lookup runs on the launching computer. Details are reported per VM below.
            $result = Invoke-HostSideAdDomainPrecheck -Domain ([string]$general['Domain']) `
                -DomainCredential $domainCredentialForNodes -ComputerName $targetName `
                -DomainOU ([string]$general['Domain OU'])
            if (-not $result.Success) { throw "VM '$vmName': $($result.Message)" }
            if ($result.OuChecked -and -not $result.OuExists) {
                throw "VM '$vmName': target OU was not found."
            }
            $jumpHostAdResults[$vmName] = $result
        }
    }
    foreach ($nodeGroup in @($plans | Group-Object Node)) {
        $node = [string]$nodeGroup.Name
        $names = @($nodeGroup.Group | ForEach-Object VMName)
        $vmIds = @{}
        foreach ($plan in $nodeGroup.Group) { $vmIds[[string]$plan.VMName] = [string]$plan.VMId }
        $shortLocal = $env:COMPUTERNAME
        $isLocal = ($node.Split('.')[0] -ieq $shortLocal)
        $arguments = @{
            ConfigFile=$configFullPath
            ADCheckMode=$ADCheckMode
            ValidateOnly=[bool]$ValidateOnly
            StartVMIfOff=[bool]$StartVMIfOff
            AllowExistingADComputer=[bool]$AllowExistingADComputer
            PSDirectMaxAttempts=$PSDirectMaxAttempts
        }
        $configuredCluster = @($nodeGroup.Group | Where-Object { $_.Cluster } | Select-Object -First 1 -ExpandProperty Cluster)
        if ($isLocal) {
            Write-Host "Execution mode: LOCALLY on $node" -ForegroundColor Cyan
            try {
                $global:HVGC_ExecutionHost = $node
                $global:HVGC_VMNames = $names
                $global:HVGC_SelectedVMIds = $vmIds
                $global:HVGC_DomainCredential = $domainCredentialForNodes
                $global:HVGC_JumpHostAdResults = $jumpHostAdResults
                $global:HVGC_LogPathOverride = $Script:LaunchLogPath
                & $PSCommandPath @arguments
            } finally {
                Remove-Variable HVGC_ExecutionHost,HVGC_VMNames,HVGC_SelectedVMIds,HVGC_DomainCredential,HVGC_JumpHostAdResults,HVGC_LogPathOverride -Scope Global -ErrorAction SilentlyContinue
            }
        } else {
            if ($configuredCluster.Count -gt 0) {
                Write-Host "Execution mode: REMOTELY on $($configuredCluster[0]) ($node) from JumpHost $($Script:LaunchComputer)" -ForegroundColor Cyan
            } else {
                Write-Host "Execution mode: REMOTELY on $node from JumpHost $($Script:LaunchComputer)" -ForegroundColor Cyan
            }
            $remoteSession = $null
            $remoteDir = 'C:\Windows\Temp\HyperVGuestConfig_' + [guid]::NewGuid().ToString('N')
            try {
                $remoteSession = New-PSSession -ComputerName $node -ErrorAction Stop
                Invoke-Command -Session $remoteSession -ScriptBlock { param($dir) New-Item -Path $dir -ItemType Directory -Force -ErrorAction Stop | Out-Null } -ArgumentList $remoteDir -ErrorAction Stop
                $remoteScript = Join-Path $remoteDir 'GuestConfig.ps1'
                $remoteConfig = Join-Path $remoteDir 'GuestConfig.txt'
                Copy-Item -LiteralPath $PSCommandPath -Destination $remoteScript -ToSession $remoteSession -ErrorAction Stop
                # Ship the same shared-function payload to the remote node.
                # The engine dot-sources it from its own directory.
                $remoteShared = Join-Path $remoteDir 'HVConfigShared.ps1'
                Copy-Item -LiteralPath $hvConfigSharedPath -Destination $remoteShared -ToSession $remoteSession -ErrorAction Stop
                Copy-Item -LiteralPath $configFullPath -Destination $remoteConfig -ToSession $remoteSession -ErrorAction Stop
                $arguments.ConfigFile = $remoteConfig
                $remoteLog = Join-Path $remoteDir (([IO.Path]::GetFileNameWithoutExtension($Script:LaunchLogPath)) + "_$node.log")
                Invoke-Command -Session $remoteSession -ScriptBlock {
                    param($scriptPath,$scriptArgs,$executionNode,$selectedVMNames,$selectedVMIds,$passedCredential,$passedAdResults,$logPath)
                    try {
                        $global:HVGC_ExecutionHost = $executionNode
                        $global:HVGC_VMNames = $selectedVMNames
                        $global:HVGC_SelectedVMIds = $selectedVMIds
                        $global:HVGC_DomainCredential = $passedCredential
                        $global:HVGC_JumpHostAdResults = $passedAdResults
                        $global:HVGC_LogPathOverride = $logPath
                        & $scriptPath @scriptArgs
                    } finally {
                        Remove-Variable HVGC_ExecutionHost,HVGC_VMNames,HVGC_SelectedVMIds,HVGC_DomainCredential,HVGC_JumpHostAdResults,HVGC_LogPathOverride -Scope Global -ErrorAction SilentlyContinue
                    }
                } -ArgumentList $remoteScript,$arguments,$node,$names,$vmIds,$domainCredentialForNodes,$jumpHostAdResults,$remoteLog -ErrorAction Stop
            } finally {
                # Transcript is closed by the remote engine. Copy it before deleting the temp folder.
                if ($remoteSession -and $remoteLog) {
                    try {
                        $destination = Join-Path (Split-Path -Parent $Script:LaunchLogPath) ([IO.Path]::GetFileName($remoteLog))
                        Copy-Item -FromSession $remoteSession -LiteralPath $remoteLog -Destination $destination -Force -ErrorAction Stop
                        Write-Host "Log saved: $destination" -ForegroundColor Cyan
                    } catch { Write-Warning "Could not retrieve log from Hyper-V host '$node': $($_.Exception.Message)" }
                }
                if ($remoteSession) {
                    try { Invoke-Command -Session $remoteSession -ScriptBlock { param($dir) Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction Stop } -ArgumentList $remoteDir -ErrorAction Stop } catch { Write-Warning "Remote temporary cleanup failed on $node : $_" }
                    Remove-PSSession $remoteSession
                }
            }
        }
    }
    return
}

# ------------------------------------------------------------
# VALIDATION / EXECUTION
# ------------------------------------------------------------

try {
    Import-Module Hyper-V -ErrorAction Stop

    $Script:LogFilePath = if ($global:HVGC_LogPathOverride) { [string]$global:HVGC_LogPathOverride } else { New-ConfigLogFilePath -ConfigFilePath $ConfigFile }
    try {
        Start-Transcript -Path $Script:LogFilePath -Force -ErrorAction Stop | Out-Null
        $Script:TranscriptStarted = $true
    }
    catch {
        $Script:TranscriptStarted = $false
        Write-Warning "Transcript could not be started: $($_.Exception.Message)"
        Write-Warning "Continuing without transcript logging."
    }

    Write-Host ""
    # Execution location is reported by the dispatcher, not by this node-local engine.
    # The remote log is copied back to the launching computer by the dispatcher.
    Write-Host "AD check mode : $ADCheckMode" -ForegroundColor Cyan
    Write-Host "Allow existing AD computer account: $AllowExistingADComputer" -ForegroundColor Cyan

    $sections = Get-ConfigSections $ConfigFile

    $sessionDomainCred = if ($global:HVGC_DomainCredential) { $global:HVGC_DomainCredential } else { Get-SessionDomainCredential }

    $errors = @()
    $warnings = @()
    $allIPs = @()
    $adJoinRequested = $false

    foreach ($s in $sections) {
        if ($global:HVGC_VMNames -and $s.General["VM Name"] -notin $global:HVGC_VMNames) { continue }
        $g = $s.General

        $BaseVMName     = $g["VM Name"]
        $VMDescription  = $g["Description"]
        $HyperVHost     = $g["Hyper-V Host"]
        $GuestUser      = $g["Guest Username"]
        $GuestPass      = $g["Guest Password"]
        $PCNameOverride = $g["PCNameOverride"]
        $PrimaryNicDnsReg = $g["PrimaryNIC(DNSreg)"]

        $Domain         = $g["Domain"]
        $ADUsersToLocalAdminsRaw = $g["ADUsers to Loc.Adm"]
        $DomainUser     = $g["Domain Username"]
        $DomainPassword = $g["Domain Password"]
        $DomainOU       = $g["Domain OU"]

        if ([string]::IsNullOrWhiteSpace($HyperVHost)) {
            $errors += "A section is missing 'Hyper-V Host'."
        }

        if ([string]::IsNullOrWhiteSpace($BaseVMName)) {
            $errors += "A section is missing 'VM Name'."
            continue
        }

        try {
            Test-BaseVMNameFormat -Name $BaseVMName -Context "Config section"
        }
        catch {
            $errors += $_.Exception.Message
            continue
        }

        if ([string]::IsNullOrWhiteSpace($GuestUser)) {
            $errors += "VM '$BaseVMName' is missing 'Guest Username'."
        }

        if ([string]::IsNullOrWhiteSpace($GuestPass)) {
            $errors += "VM '$BaseVMName' is missing 'Guest Password'."
        }

        try {
            $TargetComputerName = Get-TargetComputerName -VMName $BaseVMName -PCNameOverride $PCNameOverride
            Test-ComputerNameBasic -Name $TargetComputerName -Context "VM '$BaseVMName'"
        }
        catch {
            $errors += $_.Exception.Message
        }

        $configuredNicNamesForPrimary = @()
        foreach ($nic in $s.NetworkAdapters) {
            if (-not [string]::IsNullOrWhiteSpace($nic.Name)) {
                $configuredNicNamesForPrimary += $nic.Name
            }
        }

        if ($configuredNicNamesForPrimary.Count -gt 1 -and [string]::IsNullOrWhiteSpace($PrimaryNicDnsReg)) {
            $errors += "VM '$BaseVMName' has more than one NIC, so mandatory field 'PrimaryNIC(DNSreg)' is missing."
        }
        elseif ((-not [string]::IsNullOrWhiteSpace($PrimaryNicDnsReg)) -and (-not ($configuredNicNamesForPrimary | Where-Object { $_.Trim().ToLower() -eq $PrimaryNicDnsReg.Trim().ToLower() } | Select-Object -First 1))) {
            $errors += "VM '$BaseVMName': 'PrimaryNIC(DNSreg)' references '$PrimaryNicDnsReg', but no matching 'VM Net Adapter' block exists."
        }

        try {
            if ($g.ContainsKey("Enable RDP")) {
                [void](Convert-ToBoolFromYesNo $g["Enable RDP"] "Enable RDP")
            }

            if ($g.ContainsKey("Allow RDP-NLA only")) {
                [void](Convert-ToBoolFromYesNo $g["Allow RDP-NLA only"] "Allow RDP-NLA only")
            }

            if ($g.ContainsKey("Windows Firewall")) {
                [void](Convert-ToBoolFromYesNo $g["Windows Firewall"] "Windows Firewall")
            }
        }
        catch {
            $errors += "VM '$BaseVMName': $($_.Exception.Message)"
        }


        $adUsersToLocalAdmins = @()
        if (-not [string]::IsNullOrWhiteSpace($ADUsersToLocalAdminsRaw)) {
            $adUsersToLocalAdmins = @($ADUsersToLocalAdminsRaw.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }

        if ((-not [string]::IsNullOrWhiteSpace($Domain)) -or ($adUsersToLocalAdmins.Count -gt 0)) {
            if ($null -eq $sessionDomainCred) {
                $errors += "VM '$BaseVMName': session variable `$domainCred was not found. Run SetAdminCredentials_v1.0.ps1 in the same elevated PowerShell session before this script."
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($Domain)) {
            $adJoinRequested = $true

            if (-not [string]::IsNullOrWhiteSpace($DomainOU)) {
                if ($DomainOU -notmatch '^(?i)(OU|CN|DC)=') {
                    $warnings += "VM '$BaseVMName': Domain OU does not look like LDAP distinguished name format. Add-Computer -OUPath expects DN format."
                }
            }
        }

        if ($adUsersToLocalAdmins.Count -gt 0) {
            try {
                [void](Get-NormalizedDomainPrincipalNames -Users $adUsersToLocalAdmins -Domain $Domain)
            }
            catch {
                $errors += "VM '$BaseVMName': $($_.Exception.Message)"
            }
        }

        $gatewayUsed = $false
        $nicNamesSeen = @{}

        foreach ($nic in $s.NetworkAdapters) {
            if ([string]::IsNullOrWhiteSpace($nic.Name)) {
                $warnings += "VM '$BaseVMName': NIC block with blank 'VM Net Adapter' ignored."
                continue
            }

            if ($nicNamesSeen.ContainsKey($nic.Name)) {
                $errors += "VM '$BaseVMName': duplicate NIC name '$($nic.Name)' in config."
                continue
            }
            else {
                $nicNamesSeen[$nic.Name] = $true
            }

            if (-not [string]::IsNullOrWhiteSpace($nic.IP)) {
                $allIPs += [pscustomobject]@{
                    VM  = $BaseVMName
                    NIC = $nic.Name
                    IP  = $nic.IP
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($nic.Mask)) {
                try {
                    $nic.Prefix = Convert-SubnetMaskToPrefixLength $nic.Mask
                }
                catch {
                    $errors += "VM '$BaseVMName' NIC '$($nic.Name)': $($_.Exception.Message)"
                }
            }

            if ((-not [string]::IsNullOrWhiteSpace($nic.IP)) -and [string]::IsNullOrWhiteSpace($nic.Mask)) {
                $errors += "VM '$BaseVMName' NIC '$($nic.Name)': IP Address is specified but Subnet Mask is blank."
            }

            if ([string]::IsNullOrWhiteSpace($nic.IP)) {
                $hasDhcpInconsistency =
                    (-not [string]::IsNullOrWhiteSpace($nic.Mask)) -or
                    (-not [string]::IsNullOrWhiteSpace($nic.Gateway)) -or
                    (-not [string]::IsNullOrWhiteSpace($nic.DNS))

                if ($hasDhcpInconsistency) {
                    $errors += "VM '$BaseVMName' NIC '$($nic.Name)': IP Address is blank, so Subnet Mask, Default Gateway, and DNS Servers must also be blank."
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($nic.Gateway)) {
                if (-not $gatewayUsed) {
                    $gatewayUsed = $true
                }
                else {
                    $warnings += "VM '$BaseVMName' NIC '$($nic.Name)': additional gateway ignored."
                    $nic.Gateway = $null
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($nic.DNS)) {
                $nic.DNS = $nic.DNS.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            }
        }
    }

    $dup = $allIPs | Group-Object IP | Where-Object { $_.Count -gt 1 }

    foreach ($d in $dup) {
        $where = $d.Group | ForEach-Object { "$($_.VM)/$($_.NIC)" }
        $errors += "Duplicate IP $($d.Name) in $($where -join ', ')"
    }

    # JumpHostOnly prechecks were completed by the dispatcher before node execution.
    # The Hyper-V node does not need the ActiveDirectory module.

    if ($errors.Count -gt 0) {
        Write-Host ""
        Write-Host "Validation FAILED" -ForegroundColor Red
        $errors | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }

        if ($Script:TranscriptStarted) {
            Stop-Transcript | Out-Null
            $Script:TranscriptStarted = $false
        }

        exit 1
    }

    Write-Host ""

    if ($ValidateOnly) {
        Write-Host "ValidateOnly mode  -  runtime checks will be performed, but guest config/domain changes will not be applied." -ForegroundColor Cyan
    }
    else {
        Write-Host "ApplyMode  -  runtime checks will be performed, and guest config/domain changes will be applied." -ForegroundColor Magenta
    }

    Write-Host "Validation OK  -  no syntax/config errors found" -ForegroundColor Green

    if ($warnings.Count -gt 0) {
        Write-Host ""
        Write-Host "Validation warnings:" -ForegroundColor Yellow
        $warnings | ForEach-Object { Write-Host " - $_" -ForegroundColor Yellow }
    }

    Write-Host ""
    Write-Host "Starting per-VM checks..." -ForegroundColor Green

    $executionWarnings = @()

    foreach ($s in $sections) {
        if ($global:HVGC_VMNames -and $s.General["VM Name"] -notin $global:HVGC_VMNames) { continue }
        $g = $s.General
        $nics = $s.NetworkAdapters

        $BaseVMName         = $g["VM Name"]
        $VMDescription      = $g["Description"]
        $HyperVHost         = $g["Hyper-V Host"]
        $GuestUser          = $g["Guest Username"]
        $GuestPass          = $g["Guest Password"]
        $PCNameOverride     = $g["PCNameOverride"]
        $PrimaryNicDnsReg   = $g["PrimaryNIC(DNSreg)"]

        $Domain             = $g["Domain"]
        $ADUsersToLocalAdminsRaw = $g["ADUsers to Loc.Adm"]
        $DomainUser         = $g["Domain Username"]
        $DomainPassword     = $g["Domain Password"]
        $DomainOU           = $g["Domain OU"]

        $CurrentDisplayVMName = $null
        $TargetDisplayVMName  = $null
        $TargetComputerName   = $null
        $ResolvedHyperVHost   = $env:COMPUTERNAME
        $VmMatchType          = $null

        try {
            $TargetDisplayVMName = Get-TargetDisplayVMName -BaseVMName $BaseVMName -VMDescription $VMDescription
            $TargetComputerName  = Get-TargetComputerName -VMName $BaseVMName -PCNameOverride $PCNameOverride

            $EnableRDP = Convert-ToBoolFromYesNo $g["Enable RDP"] "Enable RDP"
            $NLA       = Convert-ToBoolFromYesNo $g["Allow RDP-NLA only"] "Allow RDP-NLA only"
            $Firewall  = Convert-ToBoolFromYesNo $g["Windows Firewall"] "Windows Firewall"

            $cred = New-Object System.Management.Automation.PSCredential (
                $GuestUser,
                (ConvertTo-SecureString $GuestPass -AsPlainText -Force)
            )

            # Per-VM credential state. Keep this local to the current config section so
            # one VM cannot accidentally reuse reconnect state from a previous VM.
            $currentGuestCred = $cred
            $reconnectCandidates = Get-ReconnectCredentialCandidates `
                -GuestUser $GuestUser `
                -GuestPass $GuestPass `
                -ComputerName $TargetComputerName
            $domainCred = $sessionDomainCred
            $domainJoinSucceeded = $false
            $postJoinCredentialCandidates = @($reconnectCandidates)

            if (-not (Test-ConfiguredHostMatchesLocalNode -ConfiguredHost $(if ($global:HVGC_ExecutionHost) { $global:HVGC_ExecutionHost } else { $HyperVHost }))) {
                $executionWarnings += "VM '$BaseVMName' skipped  -  LocalNode mode: specified Hyper-V host '$HyperVHost' does not match local host '$env:COMPUTERNAME'."
                continue
            }

            $adUsersToLocalAdmins = @()
            if (-not [string]::IsNullOrWhiteSpace($ADUsersToLocalAdminsRaw)) {
                $adUsersToLocalAdmins = Get-NormalizedDomainPrincipalNames `
                    -Users @($ADUsersToLocalAdminsRaw.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ }) `
                    -Domain $Domain
            }

            Write-Host ""
            Write-Host "---------------------------------------------"
            if ($ValidateOnly) {
                Write-Host "Validating VM on Hyper-V host $env:COMPUTERNAME"
            } else {
                Write-Host "Applying guest configuration on Hyper-V host $env:COMPUTERNAME"
            }
            Write-Host "---------------------------------------------"
            Write-ReportField 'Short VM name' $BaseVMName
            if (-not [string]::IsNullOrWhiteSpace([string]$PCNameOverride)) {
                Write-ReportField 'Windows computer name' "$TargetComputerName (PCNameOverride)" 'Yellow'
            } else {
                Write-ReportField 'Windows computer name' $TargetComputerName
            }

            try {
                $vmResolution = Resolve-VMTargetLocal -BaseVMName $BaseVMName -ExpectedVMId ([string]$global:HVGC_SelectedVMIds[$BaseVMName])

                $CurrentDisplayVMName = $vmResolution.CurrentDisplayVMName
                $ResolvedHyperVHost   = $vmResolution.ResolvedHyperVHost
                $VmMatchType          = $vmResolution.MatchType

                # The execution line already identifies the host/cluster.

                # Approved matrix: a single ShortNameMatch processes automatically.
                # MultipleShortNameMatches require selection and confirmation.
                if ($vmResolution.RequiresConfirmation) {
                    Show-VMTargetCandidates -BaseVMName $BaseVMName -Candidates $vmResolution.Candidates

                    # Both modes select a concrete VM. Only Apply requires a
                    # separate confirmation after selecting the candidate.
                    $selectedCandidate = Select-VMTargetCandidate -BaseVMName $BaseVMName -Candidates $vmResolution.Candidates
                    if (-not $selectedCandidate) {
                        $executionWarnings += "VM '$BaseVMName' skipped  -  no VM candidate selected"
                        continue
                    }

                    $CurrentDisplayVMName = $selectedCandidate.Name
                    $VmMatchType = "$VmMatchType/UserSelected"
                    Write-Host "Selected VM object      : $CurrentDisplayVMName" -ForegroundColor Green

                    if (-not $ValidateOnly) {
                        $approved = Confirm-HVSelectedVMMatch `
                            -BaseVMName $BaseVMName `
                            -CurrentDisplayVMName $CurrentDisplayVMName
                        if (-not $approved) {
                            $executionWarnings += "VM '$BaseVMName' skipped  -  selected VM '$CurrentDisplayVMName' was not confirmed"
                            continue
                        }
                    }
                }

                Write-ReportField 'Full VM name' $CurrentDisplayVMName
                Write-Host "VM match type: $VmMatchType" -ForegroundColor Cyan
                Write-Host "---------------------------------------------"
                Write-Host $(if ($ValidateOnly) { 'Validation' } else { 'Pre-configuration checks' }) -ForegroundColor Cyan
                Write-Host "---------------------------------------------"
                Write-ReportField 'Configuration syntax' 'OK' 'Green'
                Write-ReportField 'VM found on Hyper-V host' 'OK' 'Green'


            }
            catch {
                $msg = ($_ | Out-String).Trim()
                throw "VMRESOLVEFAIL: $msg"
            }

            try {
                Get-VM -Name $CurrentDisplayVMName -ErrorAction Stop | Out-Null
                Write-Host "Local Hyper-V access OK" -ForegroundColor Green
            }
            catch {
                throw "HVHOSTEXECFAIL: $($_.Exception.Message)"
            }

            $hostAdapterPrecheck = $null
            try {
                $hostAdapterPrecheck = & $sbHostAdapterPrecheck $CurrentDisplayVMName $nics
                Write-ReportField 'VM network adapter' 'OK' 'Green'
            }
            catch {
                $msg = ($_ | Out-String).Trim()
                throw "BASEPRECHECKFAIL: $msg"
            }

            # Validation is non-applying by default. Explicit -StartVMIfOff permits
            # only an Off -> Running transition, after name/VM-ID resolution and
            # host-side checks. Saved, Paused and transitional states are refused.
            if ($ValidateOnly) {
                $validationVM = Get-VM -Name $CurrentDisplayVMName -ErrorAction Stop
                $validationVMState = [string]$validationVM.State
                if ($validationVMState -ne 'Running') {
                    if ($StartVMIfOff -and $validationVMState -eq 'Off') {
                        # Recheck the selected identity immediately before power-on.
                        $expectedId = [string]$global:HVGC_SelectedVMIds[$BaseVMName]
                        if ([string]::IsNullOrWhiteSpace($expectedId) -or [string]$validationVM.Id -ine $expectedId) {
                            throw "HVHOSTEXECFAIL: Selected VM identity changed before startup for '$BaseVMName'; expected ID '$expectedId', actual ID '$($validationVM.Id)'. No startup attempted."
                        }
                        Write-Host "INFO: StartVMIfOff: starting '$CurrentDisplayVMName' (VM ID $expectedId) for validation..." -ForegroundColor Cyan
                        try {
                            Start-VM -VM $validationVM -ErrorAction Stop | Out-Null
                        } catch {
                            throw "HVHOSTEXECFAIL: Could not start selected VM '$CurrentDisplayVMName' for validation: $($_.Exception.Message)"
                        }
                        Write-Host "INFO: VM startup requested. Continuing guest readiness and validation checks; VM will remain running." -ForegroundColor Cyan
                    } else {
                        $reason = if ($StartVMIfOff) { "-StartVMIfOff supports only Off VMs; '$validationVMState' state will not be changed." } else { 'VM state unchanged.' }
                        Write-Warning "VM '$BaseVMName': selected VM '$CurrentDisplayVMName' is $validationVMState. Host-side checks completed; guest checks skipped in ValidateOnly ($reason)"
                        continue
                    }
                }
            }

            try {
                & $sbGuestReady $CurrentDisplayVMName $currentGuestCred | Out-Null
                Write-ReportField 'Guest heartbeat' 'Ready' 'Green'
                Write-ReportField 'PowerShell Direct' 'Ready' 'Green'
            }
            catch {
                $msg = $_.Exception.Message
                if ($msg -like "AUTHFAIL:*" -or $msg -like "GUESTREADYTIMEOUT:*") {
                    throw $msg
                }
                else {
                    throw "GUESTCHECKFAIL: $msg"
                }
            }

            $precheck = $null
            try {
                $precheck = & $sbGuestAdapterPrecheck $CurrentDisplayVMName $currentGuestCred $TargetComputerName

                if (-not $precheck -or -not $precheck.Success) {
                    throw "Guest-side NIC / domain-state precheck did not return a success result."
                }

                Write-Host "Guest-side NIC / domain-state precheck OK" -ForegroundColor Green

                if ($precheck.PartOfDomain) {
                    Write-Warning "Guest is currently domain-joined to '$($precheck.CurrentDomain)'. FULL isolation -> WORKGROUP -> rename -> restart (still isolated) -> reconnect only PrimaryNIC(DNSreg) -> join-domain flow will be used."
                }
                else {
                    Write-Host "Guest is not currently domain-joined." -ForegroundColor Green
                }
            }
            catch {
                $msg = ($_ | Out-String).Trim()
                throw "BASEPRECHECKFAIL: $msg"
            }

           if ($ValidateOnly) {
                Write-Host "INFO: ValidateOnly performs non-invasive guest checks only. Exact multi-NIC mapping by disconnect/reconnect is skipped in ValidateOnly and performed only in apply mode." -ForegroundColor Cyan
            }

            $ipConflict = $false

            foreach ($nic in @($hostAdapterPrecheck.AdapterMap)) {
                if ([string]::IsNullOrWhiteSpace($nic.IP)) {
                    continue
                }

                $vacant = Test-IPLooksVacant -IPAddress $nic.IP

                if ($vacant) {
                    continue
                }

                $guestIpMatch = $null

                try {
                    $guestIpMatch = Get-GuestIPv4MatchLocal `
                        -VMName $CurrentDisplayVMName `
                        -Credential $currentGuestCred `
                        -IPAddress $nic.IP
                }
                catch {
                    $msg = $_.Exception.Message
                    throw "IPCHECKFAIL: Could not verify whether VM '$BaseVMName' already owns IP '$($nic.IP)'. $msg"
                }

                if ($guestIpMatch.Found) {
                    $ifText = $guestIpMatch.InterfaceAlias
                    if ([string]::IsNullOrWhiteSpace($ifText)) {
                        $ifText = "InterfaceIndex $($guestIpMatch.InterfaceIndex)"
                    }

                    if ($ValidateOnly) {
                        Write-Warning "IP '$($nic.IP)' is already assigned to Network Interface '$ifText' on VM '$CurrentDisplayVMName'."
                    }
                    else {
                        Write-Warning "IP '$($nic.IP)' is already assigned to Network Interface '$ifText' on VM '$CurrentDisplayVMName'. Updating IP settings..."
                    }

                    continue
                }

                Write-Warning "VM '$BaseVMName' NIC '$($nic.Name)': IP address '$($nic.IP)' responds to ping and is not currently assigned to actual VM '$CurrentDisplayVMName'. Skipping this VM."
                $executionWarnings += "VM '$BaseVMName' skipped (IP '$($nic.IP)' is in use by another device)"
                $ipConflict = $true
            }

            if ($ipConflict) {
                continue
            }

            Write-Host "IP vacancy check OK" -ForegroundColor Green

            $skipDomainJoinBecauseComputerExists = $false

            if ((-not [string]::IsNullOrWhiteSpace($Domain)) -and $ADCheckMode -eq "JumpHostOnly") {
                $hostSideDomainPrecheck = $null

                try {
                    if (-not $global:HVGC_JumpHostAdResults -or
                        -not $global:HVGC_JumpHostAdResults.ContainsKey($BaseVMName)) {
                        throw "Missing JumpHost AD precheck result for VM '$BaseVMName'."
                    }
                    $hostSideDomainPrecheck = $global:HVGC_JumpHostAdResults[$BaseVMName]
                }
                catch {
                    $msg = $_.Exception.Message
                    throw $msg
                }

                if ($hostSideDomainPrecheck.Success) {
                    Write-ReportField 'AD object check' 'OK (JumpHost)' 'Green'
                    Write-ReportField 'Target AD computer account' $TargetComputerName
                    if ($hostSideDomainPrecheck.ComputerExists) {
                        Write-ExistingADComputerDomainJoinWarning `
                            -VMName $BaseVMName `
                            -ComputerName $TargetComputerName `
                            -Domain $Domain `
                            -AllowExistingADComputer:$AllowExistingADComputer `
                            -ValidateOnly:$ValidateOnly

                        if ($AllowExistingADComputer) {
                            $executionWarnings += "VM '$BaseVMName': AD computer '$TargetComputerName' already exists; -AllowExistingADComputer specified, so domain join is allowed"
                            $skipDomainJoinBecauseComputerExists = $false
                        }
                        else {
                            $executionWarnings += "VM '$BaseVMName': domain join skipped because AD computer '$TargetComputerName' already exists"
                            $skipDomainJoinBecauseComputerExists = $true
                        }
                    }
                    else {
                        Write-Host "JumpHost AD lookup using supplied domain credentials: target computer name is vacant" -ForegroundColor Green
                    }

                    if ($hostSideDomainPrecheck.OuChecked) {
                        if ($hostSideDomainPrecheck.OuExists) {
                            Write-Host "OU existence check OK" -ForegroundColor Green
                        }
                        else {
                            throw "OUCHECKFAIL: OU '$DomainOU' was not found in domain '$Domain'."
                        }
                    }
                }
                else {
                    throw "DOMAINCHECKFAIL: $($hostSideDomainPrecheck.Message)"
                }
            }
            elseif ((-not [string]::IsNullOrWhiteSpace($Domain)) -and $ADCheckMode -eq "GuestOnly" -and $ValidateOnly) {
                try {
                    $guestSideDomainPrecheck = Invoke-GuestSideTargetDomainPrecheck `
                        -VMName $CurrentDisplayVMName `
                        -Credential $currentGuestCred `
                        -Domain $Domain `
                        -DomainCredential $domainCred `
                        -ComputerName $TargetComputerName `
                        -DomainOU $DomainOU

                    if ($guestSideDomainPrecheck.ComputerExists) {
                        Write-ExistingADComputerDomainJoinWarning `
                            -VMName $BaseVMName `
                            -ComputerName $TargetComputerName `
                            -Domain $Domain `
                            -AllowExistingADComputer:$AllowExistingADComputer `
                            -ValidateOnly:$ValidateOnly

                        if ($AllowExistingADComputer) {
                            $executionWarnings += "VM '$BaseVMName': AD computer '$TargetComputerName' already exists; -AllowExistingADComputer specified, so domain join would be allowed in Apply mode"
                            $skipDomainJoinBecauseComputerExists = $false
                        }
                        else {
                            $executionWarnings += "VM '$BaseVMName': domain join would be skipped because AD computer '$TargetComputerName' already exists"
                            $skipDomainJoinBecauseComputerExists = $true
                        }
                    }
                    else {
                        Write-Host "Guest-side target-domain lookup: target computer name is vacant" -ForegroundColor Green
                    }

                    if ($guestSideDomainPrecheck.OuChecked) {
                        if ($guestSideDomainPrecheck.OuExists) {
                            Write-Host "Guest-side OU existence check OK" -ForegroundColor Green
                        }
                        else {
                            throw "OUCHECKFAIL: OU '$DomainOU' was not found in domain '$Domain'."
                        }
                    }
                }
                catch {
                    $msg = ($_ | Out-String).Trim()

                    if ($msg -like 'DOMAINAUTHFAIL:*') {
                        throw $msg
                    }
                    elseif ($msg -like 'DOMAINCONNECTFAIL:*') {
                        throw $msg
                    }
                    elseif ($msg -like 'OUCHECKFAIL:*') {
                        throw $msg
                    }
                    else {
                        throw "DOMAINCHECKFAIL: $msg"
                    }
                }
            }

            if ($ValidateOnly) {
                Write-ReportField 'Guest OS checks' 'OK' 'Green'
                Write-Host "Validation completed for '$BaseVMName'. No changes were applied." -ForegroundColor Green
                continue
            }

            # ------------------------------------------------------------
            # Mapping phase (apply mode only, because it is intrusive)
            # ------------------------------------------------------------

            $resolvedMap = $null
            try {
                $resolvedMap = & $sbMapGuestAdaptersByDisconnect `
                    $CurrentDisplayVMName `
                    $currentGuestCred `
                    @($hostAdapterPrecheck.AdapterMap)

                if (-not $resolvedMap.Success) {
                    throw "Guest adapter mapping did not return success."
                }

                $hostAdapterPrecheck = $resolvedMap
                Write-Host "Guest NIC mapping completed successfully" -ForegroundColor Green
            }
            catch {
                $msg = ($_ | Out-String).Trim()
                throw "BASEPRECHECKFAIL: $msg"
            }

            $effectivePrimaryNicDnsReg = $PrimaryNicDnsReg
            if ([string]::IsNullOrWhiteSpace($effectivePrimaryNicDnsReg) -and @($hostAdapterPrecheck.AdapterMap).Count -eq 1) {
                $effectivePrimaryNicDnsReg = @($hostAdapterPrecheck.AdapterMap)[0].Name
            }

            $primaryIsolationApplied = $false
            $allVmAdapterStateSnapshot = @()
            try {
                $fullIsolationResult = & $sbDisconnectAllVmNetworkAdapters $CurrentDisplayVMName
                if (-not $fullIsolationResult.Success) {
                    throw "Full VM network isolation did not return success."
                }

                $allVmAdapterStateSnapshot = @($fullIsolationResult.AdapterStates)
                if ($allVmAdapterStateSnapshot.Count -lt 1) {
                    throw "Full VM network isolation did not return any adapter-state snapshot."
                }

                $primaryIsolationApplied = $true
                Write-Host "Full VM network isolation applied successfully" -ForegroundColor Green
            }
            catch {
                $msg = ($_ | Out-String).Trim()
                throw "BASECONFIGFAIL: $msg"
            }

            $prepareResult = $null
            try {
                $prepareResult = & $sbPrepareStandaloneAndRename `
                    $CurrentDisplayVMName `
                    $currentGuestCred `
                    $TargetComputerName `
                    $GuestUser `
                    $GuestPass `
                    @($hostAdapterPrecheck.AdapterMap)

                Write-Host "Standalone/rename step completed successfully" -ForegroundColor Green
            }
            catch {
                $msg = ($_ | Out-String).Trim()
                throw "BASECONFIGFAIL: $msg"
            }

            if ($prepareResult.RestartRequired) {
                try {
                    & $sbWaitGuestHeartbeatOnly $CurrentDisplayVMName | Out-Null
                }
                catch {
                    $msg = ($_ | Out-String).Trim()
                    throw "POSTRENAMEFAIL: $msg"
                }

                try {
                    $reconnectCandidates = Get-ReconnectCredentialCandidates `
                        -GuestUser $GuestUser `
                        -GuestPass $GuestPass `
                        -ComputerName $TargetComputerName

                    $currentGuestCred = Wait-GuestPsDirectReconnect `
                        -VMName $CurrentDisplayVMName `
                        -CredentialCandidates $reconnectCandidates `
                        -InitialDelaySec 20 `
                        -AttemptsPerCredential 8 `
                        -DelayBetweenAttemptsSec 10
                }
                catch {
                    $msg = ($_ | Out-String).Trim()
                    if ($msg -like "AUTHFAIL:*") {
                        throw $msg
                    }
                    else {
                        throw "POSTRENAMEFAIL: $msg"
                    }
                }
            }

            try {
                & $sbReconnectPrimaryVmNetworkAdapterOnly `
                    $CurrentDisplayVMName `
                    @($hostAdapterPrecheck.AdapterMap) `
                    @($allVmAdapterStateSnapshot) `
                    $effectivePrimaryNicDnsReg | Out-Null

                Write-Host "PrimaryNIC(DNSreg) isolation applied successfully" -ForegroundColor Green
            }
            catch {
                $msg = ($_ | Out-String).Trim()
                throw "BASECONFIGFAIL: $msg"
            }

            try {
                & $sbApplyGuestNetworkAndLocalConfig `
                    $CurrentDisplayVMName `
                    $currentGuestCred `
                    $EnableRDP `
                    $NLA `
                    $Firewall `
                    @($hostAdapterPrecheck.AdapterMap) | Out-Null

                Write-Host "Network / RDP / firewall config applied successfully" -ForegroundColor Green
            }
            catch {
                $msg = ($_ | Out-String).Trim()
                throw "BASECONFIGFAIL: $msg"
            }

            if ((-not [string]::IsNullOrWhiteSpace($Domain)) -and (-not $skipDomainJoinBecauseComputerExists) -and $ADCheckMode -eq "GuestOnly") {
                try {
                    $guestSideDomainPrecheck = Invoke-GuestSideTargetDomainPrecheck `
                        -VMName $CurrentDisplayVMName `
                        -Credential $currentGuestCred `
                        -Domain $Domain `
                        -DomainCredential $domainCred `
                        -ComputerName $TargetComputerName `
                        -DomainOU $DomainOU

                    if ($guestSideDomainPrecheck.ComputerExists) {
                        Write-ExistingADComputerDomainJoinWarning `
                            -VMName $BaseVMName `
                            -ComputerName $TargetComputerName `
                            -Domain $Domain `
                            -AllowExistingADComputer:$AllowExistingADComputer `
                            -ValidateOnly:$ValidateOnly

                        if ($AllowExistingADComputer) {
                            $executionWarnings += "VM '$BaseVMName': AD computer '$TargetComputerName' already exists; -AllowExistingADComputer specified, so domain join is allowed"
                            $skipDomainJoinBecauseComputerExists = $false
                        }
                        else {
                            $executionWarnings += "VM '$BaseVMName': domain join skipped because AD computer '$TargetComputerName' already exists"
                            $skipDomainJoinBecauseComputerExists = $true
                        }
                    }
                    else {
                        Write-Host "Guest-side target-domain lookup: target computer name is vacant" -ForegroundColor Green
                    }

                    if ($guestSideDomainPrecheck.OuChecked) {
                        if ($guestSideDomainPrecheck.OuExists) {
                            Write-Host "Guest-side OU existence check OK" -ForegroundColor Green
                        }
                        else {
                            throw "OUCHECKFAIL: OU '$DomainOU' was not found in domain '$Domain'."
                        }
                    }
                }
                catch {
                    $msg = ($_ | Out-String).Trim()

                    if ($msg -like 'DOMAINAUTHFAIL:*') {
                        throw $msg
                    }
                    elseif ($msg -like 'DOMAINCONNECTFAIL:*') {
                        throw $msg
                    }
                    elseif ($msg -like 'OUCHECKFAIL:*') {
                        throw $msg
                    }
                    else {
                        throw "DOMAINCHECKFAIL: $msg"
                    }
                }
            }

            if ((-not [string]::IsNullOrWhiteSpace($Domain)) -and (-not $skipDomainJoinBecauseComputerExists)) {
                try {
                    & $sbJoinDomain $CurrentDisplayVMName $currentGuestCred $Domain $domainCred $DomainOU $TargetComputerName | Out-Null
                    $domainJoinSucceeded = $true
                    Write-Host "$TargetComputerName joined domain successfully" -ForegroundColor Green
                }
                catch {
                    $msg = ($_ | Out-String).Trim()

                    if (Test-ErrorLooksLikeAuthFailure $msg) {
                        throw "DOMAINAUTHFAIL: $msg"
                    }
                    elseif (Test-ErrorLooksLikeNameOrConnectivityFailure $msg) {
                        throw "DOMAINCONNECTFAIL: $msg"
                    }
                    else {
                        throw "DOMAINJOINFAIL: $msg"
                    }
                }

                try {
                    & $sbWaitGuestHeartbeatOnly $CurrentDisplayVMName | Out-Null
                }
                catch {
                    $msg = ($_ | Out-String).Trim()
                    throw "POSTDOMAINJOINFAIL: $msg"
                }

                try {
                    $localReconnectCandidates = Get-ReconnectCredentialCandidates `
                        -GuestUser $GuestUser `
                        -GuestPass $GuestPass `
                        -ComputerName $TargetComputerName

                    if ($domainJoinSucceeded -and $null -ne $domainCred) {
                        Write-Host "INFO: Domain join succeeded. Trying domain credential first for post-join PowerShell Direct reconnect; local credentials remain fallback." -ForegroundColor Cyan
                        $postJoinCredentialCandidates = @($domainCred) + @($localReconnectCandidates)
                    }
                    else {
                        $postJoinCredentialCandidates = @($localReconnectCandidates)
                    }

                    $reconnectCandidates = @($postJoinCredentialCandidates)

                    $currentGuestCred = Wait-GuestPsDirectReconnect `
                        -VMName $CurrentDisplayVMName `
                        -CredentialCandidates $postJoinCredentialCandidates `
                        -InitialDelaySec 10 `
                        -AttemptsPerCredential 8 `
                        -DelayBetweenAttemptsSec 10
                }
                catch {
                    $msg = ($_ | Out-String).Trim()
                    if ($msg -like "AUTHFAIL:*") {
                        throw $msg
                    }
                    else {
                        throw "POSTDOMAINJOINFAIL: $msg"
                    }
                }
            }

            if ($adUsersToLocalAdmins.Count -gt 0) {
                try {
                    # Refresh PowerShell Direct credential immediately before local-admins work.
                    # If the VM was just joined to the domain, $reconnectCandidates is domain-first
                    # with local guest credentials as fallback. If no domain join was performed,
                    # it remains local-credentials-only.
                    $currentGuestCred = Wait-GuestPsDirectReconnect `
                        -VMName $CurrentDisplayVMName `
                        -CredentialCandidates $reconnectCandidates `
                        -InitialDelaySec 10 `
                        -AttemptsPerCredential 10 `
                        -DelayBetweenAttemptsSec 10

                    $localAdminResult = & $sbAddDomainUsersToLocalAdmins `
                        $CurrentDisplayVMName `
                        $currentGuestCred `
                        @($adUsersToLocalAdmins)

                    foreach ($addedUser in @($localAdminResult.Added)) {
                        Write-Host "Local Administrators: added '$addedUser'." -ForegroundColor Green
                    }

                    foreach ($skippedUser in @($localAdminResult.Skipped)) {
                        Write-Host "Local Administrators: '$skippedUser' is already a member." -ForegroundColor Cyan
                    }

                    foreach ($failedUser in @($localAdminResult.Failed)) {
                        Write-Warning "Local Administrators: failed to add '$($failedUser.User)'. $($failedUser.Message)"
                    }

                    if ((@($localAdminResult.Added).Count -eq 0) -and (@($localAdminResult.Skipped).Count -eq 0) -and (@($localAdminResult.Failed).Count -eq 0)) {
                        Write-Host "Local Administrators: no users were processed." -ForegroundColor Yellow
                    }
                }
                catch {
                    $msg = ($_ | Out-String).Trim()
                    Write-Warning "LOCALADMINSFAIL: domain users were not added to local Administrators on VM '$BaseVMName'. $msg"
                    $executionWarnings += "VM '$BaseVMName' completed with warning  -  LOCALADMINSFAIL: domain users were not added to local Administrators. $msg"
                }
            }

            if ($primaryIsolationApplied) {
                try {
                    & $sbRestoreVmNetworkAdapterStates $CurrentDisplayVMName @($allVmAdapterStateSnapshot) | Out-Null
                    Write-Host "VM adapters restored to original connection state successfully" -ForegroundColor Green
                    $primaryIsolationApplied = $false
                }
                catch {
                    $msg = ($_ | Out-String).Trim()
                    throw "BASECONFIGFAIL: $msg"
                }
            }

            try {
                & $sbTriggerDnsRegistration $CurrentDisplayVMName $currentGuestCred
            }
            catch {
                $msg = ($_ | Out-String).Trim()
                $executionWarnings += "VM '$BaseVMName': DNS registration trigger failed  -  $msg"
            }

            Write-Host "VM '$BaseVMName' processed successfully (actual VM object: '$CurrentDisplayVMName')" -ForegroundColor Green
        }
        catch {
            if ($primaryIsolationApplied) {
                try {
                    & $sbRestoreVmNetworkAdapterStates $CurrentDisplayVMName @($allVmAdapterStateSnapshot) | Out-Null
                    Write-Host "VM adapters restored to original connection state successfully" -ForegroundColor Green
                    $primaryIsolationApplied = $false
                }
                catch {
                    $restoreMsg = ($_ | Out-String).Trim()
                    $executionWarnings += "VM '$BaseVMName': failed restoring VM adapters after error  -  $restoreMsg"
                }
            }
            $msg = $_.Exception.Message
            $warningText = $null

            if ($msg -like "GUESTREADYTIMEOUT:*") {
                $warningText = "VM '$BaseVMName' skipped  -  $msg"
            }
            elseif ($msg -like "AUTHFAIL:*") {
                $warningText = "VM '$BaseVMName' skipped  -  $msg"
            }
            elseif ($msg -like "VMRESOLVEFAIL:*") {
                $warningText = "VM '$BaseVMName' skipped  -  $msg"
            }
            elseif ($msg -like "HVHOSTEXECFAIL:*") {
                $warningText = "VM '$BaseVMName' skipped  -  local Hyper-V access check failed"
            }
            elseif ($msg -like "GUESTCHECKFAIL:*") {
                $warningText = "VM '$BaseVMName' skipped  -  $msg"
            }
            elseif ($msg -like "BASEPRECHECKFAIL:*") {
                $warningText = "VM '$BaseVMName' skipped  -  $msg"
            }
            elseif ($msg -like "IPCHECKFAIL:*") {
                $warningText = "VM '$BaseVMName' skipped  -  $msg"
            }
            elseif ($msg -like "BASECONFIGFAIL:*") {
                $warningText = "VM '$BaseVMName' skipped  -  $msg"
            }
            elseif ($msg -like "POSTRENAMEFAIL:*") {
                $warningText = "VM '$BaseVMName' skipped  -  $msg"
            }
            elseif ($msg -like "POSTDOMAINJOINFAIL:*") {
                $warningText = "VM '$BaseVMName' skipped  -  $msg"
            }
            elseif ($msg -like "DOMAINAUTHFAIL:*") {
                $warningText = "VM '$BaseVMName' skipped  -  wrong domain credentials"
            }
            elseif ($msg -like "DOMAINCONNECTFAIL:*") {
                $warningText = "VM '$BaseVMName' skipped  -  domain name is wrong or domain controller is unreachable"
            }
            elseif ($msg -like "DOMAINCHECKFAIL:*") {
                $warningText = "VM '$BaseVMName' skipped  -  $msg"
            }
            elseif ($msg -like "OUCHECKFAIL:*") {
                $warningText = "VM '$BaseVMName' skipped  -  $msg"
            }
            elseif ($msg -like "DOMAINJOINFAIL:*") {
                $warningText = "VM '$BaseVMName' skipped  -  $msg"
            }
            else {
                $warningText = "VM '$BaseVMName' skipped  -  $msg"
            }

            # v1.71: print the failure immediately inside the current VM block,
            # while still preserving the same final Execution warnings summary.
            if ($msg -notlike "GUESTREADYTIMEOUT:*") {
                Write-Warning $warningText
            }
            $executionWarnings += $warningText

            continue
        }
    }

    if ($executionWarnings.Count -gt 0) {
        Write-Host ""
        Write-Host "Execution warnings:" -ForegroundColor Yellow
        $executionWarnings | ForEach-Object { Write-Host " - $_" -ForegroundColor Yellow }
    }

    Write-Host ""
    Write-Host "Script finished." -ForegroundColor Green
}
finally {
    if ($Script:TranscriptStarted) {
        Stop-Transcript | Out-Null
        $Script:TranscriptStarted = $false
    }

    if (-not [string]::IsNullOrWhiteSpace($Script:LogFilePath)) {
        if (-not $global:HVGC_ExecutionHost -or $Script:LogFilePath -notlike 'C:\Windows\Temp\HyperVGuestConfig_*') {
            Write-Host "Log saved: $Script:LogFilePath" -ForegroundColor Cyan
        }
    }
}
