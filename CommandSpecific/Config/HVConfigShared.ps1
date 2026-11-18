# Purpose: Convert-HVYesNo - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# AUTO-GENERATED from canonical Shared functions. Do not edit manually.

# Regenerate with Tests/Build-HVConfigSharedPayload.ps1.

# Converts hVYes No for the calling workflow.
function Convert-HVYesNo {
    param(
        [AllowNull()][string]$Value,
        [Parameter(Mandatory = $true)][string]$FieldName
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }

    switch ($Value.Trim().ToLower()) {
        'yes'   { return $true }
        'y'     { return $true }
        'on'    { return $true }
        'true'  { return $true }
        'no'    { return $false }
        'n'     { return $false }
        'off'   { return $false }
        'false' { return $false }
        default { throw "Invalid value for '$FieldName': '$Value'. Expected Yes/No, Y/N, On/Off, or True/False." }
    }
}

# Checks hVShort VMName for the calling workflow.
function Test-HVShortVMName {
    param(
        [Parameter(Mandatory = $true)][string]$BaseVMName,
        [string]$Pattern,
        [string]$Context
    )
    if ([string]::IsNullOrWhiteSpace($BaseVMName)) {
        if ($Context) { throw "$Context VM Name is blank." }
        throw "Short VM name is blank."
    }
    if ([string]::IsNullOrWhiteSpace($Pattern)) { $Pattern = $script:ShortVMNamePattern }
    if ([string]::IsNullOrWhiteSpace($Pattern)) { $Pattern = '^[A-Za-z0-9]{10}$' }
    if ($BaseVMName -notmatch $Pattern) {
        if ($Context -and $Pattern -eq '^[A-Za-z0-9]{10}$') {
            throw "$Context VM Name '$BaseVMName' must be exactly 10 alphanumeric characters."
        }
        throw "Short VM name '$BaseVMName' does not match configured VMNaming.ShortNamePattern: $Pattern"
    }
}

# Retrieves hVDisplay VMName for the calling workflow.
function Get-HVDisplayVMName {
    param(
        [Parameter(Mandatory = $true)][string]$BaseVMName,
        [AllowNull()][string]$VMDescription,
        [switch]$ConfigDescriptionStyle
    )
    if ($ConfigDescriptionStyle) {
        if ([string]::IsNullOrWhiteSpace($VMDescription)) { return $BaseVMName.Trim() }
        return ('{0} - {1}' -f $BaseVMName.Trim(), $VMDescription.Trim())
    }
    if ([string]::IsNullOrWhiteSpace($VMDescription)) { return $BaseVMName }
    "$BaseVMName $($VMDescription.TrimStart())"
}

# Retrieves hVVMName Classification for the calling workflow.
function Get-HVVMNameClassification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ShortVMName,
        [Parameter(Mandatory)][string]$ExistingVMName
    )
    $short = $ShortVMName.Trim()
    $name = $ExistingVMName.Trim()
    if ([string]::IsNullOrWhiteSpace($short) -or [string]::IsNullOrWhiteSpace($name)) { return $null }
    if ($name.IndexOf($short, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return 'ShortNameMatch' }
    return $null
}

# Finds potential VM matches before choosing a specific target.
function Find-HVVMMatches {
    [CmdletBinding(DefaultParameterSetName='Create')]
    param(
        [Parameter(Mandatory=$true,ParameterSetName='Create')][string]$NamePattern,
        [Parameter(ParameterSetName='Create')][switch]$Silent,
        [Parameter(Mandatory=$true,ParameterSetName='Config')][string]$ShortVMName,
        [Parameter(Mandatory=$true,ParameterSetName='Config')][object[]]$VMs
    )
    if ($PSCmdlet.ParameterSetName -eq 'Create') {
        # Preserve Create's original discovery behavior and error handling.
        @(Get-VMNamesSafeLocal -NamePattern $NamePattern -Silent:$Silent)
        return
    }
    # One case-insensitive literal ShortName match is selected automatically.
    $name = $ShortVMName.Trim()
    $seen = @{}
    $candidates = @()
    foreach ($vm in @($VMs)) {
        if ($null -eq $vm -or [string]::IsNullOrWhiteSpace([string]$vm.Name)) { continue }
        $display = ([string]$vm.Name).Trim()
        $kind = Get-HVVMNameClassification -ShortVMName $name -ExistingVMName $display
        if ($null -eq $kind) { continue }
        $identity = if ($null -ne $vm.PSObject.Properties['Id'] -and $null -ne $vm.Id) { [string]$vm.Id } else { $display.ToUpperInvariant() }
        if ($seen.ContainsKey($identity)) { continue }
        $seen[$identity] = $true
        $candidates += [pscustomobject]@{ VM = $vm; Kind = $kind }
    }
    if ($candidates.Count -eq 0) { throw "NoAnyMatches: No VM matched ShortName '$ShortVMName' on local host '$env:COMPUTERNAME'." }
    $allVMs = @($candidates | ForEach-Object { $_.VM })
    $kind = if ($candidates.Count -eq 1) { 'ShortNameMatch' } else { 'MultipleShortNameMatches' }
    return [pscustomobject]@{MatchType=$kind;RequiresConfirmation=($candidates.Count -gt 1);CurrentDisplayVMName=$(if($candidates.Count -eq 1){$allVMs[0].Name}else{$null});Candidates=$allVMs}
}

# Queries cluster availability and the nodes eligible for VM operations.
function Get-HVClusterProbe {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    Import-Module FailoverClusters -ErrorAction Stop
    $cluster = Get-Cluster -Name $Name -ErrorAction Stop
    $nodes = @(Get-ClusterNode -Cluster $cluster.Name -ErrorAction Stop |
        Where-Object State -eq 'Up' | ForEach-Object { $_.Name })
    if (-not $nodes.Count) { throw "No online nodes in cluster $($cluster.Name)" }
    [pscustomobject]@{ ClusterName = $cluster.Name; Nodes = @($nodes) }
}

# Retrieves hVTarget Type for the calling workflow.
function Get-HVTargetType {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name,[object[]]$Items)
    Get-HVClusterPlacement -Name $Name -Items $Items
}

# Parses VM groups, per-VM tags, and shared parameters from the Create configuration.
function Read-HVVMConfig {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $lines = Get-Content -LiteralPath $resolvedPath

    $sections = @()
    $currentVmList = @()
    $currentVm = $null
    $currentParams = $null
    $mode = $null

    $lineNumber = 0
    $seenNetworkKeys = @{}
    foreach ($rawLine in $lines) {
        $lineNumber++
        $line = $rawLine.TrimEnd()
        $trimmed = $line.Trim()

        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        if ($trimmed -match '^\s*#') { continue }
        if ($trimmed -match '^=+.*Template.*=+$') { continue }

        if ($trimmed -match '^=+\s*VM Names\s*=+$') {
            if ($currentVm) {
                $currentVmList += $currentVm
                $currentVm = $null
            }

            if ($currentVmList.Count -gt 0 -and $currentParams) {
                foreach ($vmItem in $currentVmList) {
                    $sections += [pscustomobject]@{ VM = $vmItem; Params = $currentParams }
                }
            }

            $currentVmList = @()
            $currentVm = $null
            $currentParams = $null
            $mode = 'VM'
            continue
        }

        if ($trimmed -match '^-+\s*VM Parameters\s*-+$') {
            if ($currentVm) {
                $currentVmList += $currentVm
                $currentVm = $null
            }

            if ($currentVmList.Count -eq 0) {
                throw "Found 'VM Parameters' block before any VM entries."
            }

            $currentParams = @{}
            $seenNetworkKeys = @{}
            $mode = 'Params'
            continue
        }

        if ($trimmed -match '^\s*([^:]+?)\s*:\s*(.*?)\s*$') {
            $key = $matches[1].Trim()
            $value = $matches[2]

            switch ($mode) {
                'VM' {
                    if ($key -eq 'VM Name') {
                        if ($currentVm) { $currentVmList += $currentVm }
                        $currentVm = @{}
                        $currentVm['VM Name'] = $value
                    }
                    else {
                        if (-not $currentVm) { throw "Found VM field '$key' before 'VM Name'." }
                        $currentVm[$key] = $value
                    }
                }
                'Params' {
                    if ($key -match '^(Network|VLAN)_(\d+)$') {
                        $kind = $matches[1]
                        $index = [int]$matches[2]
                        $canonicalKey = '{0}_{1}' -f $kind,$index
                        $vmNames = (@($currentVmList | ForEach-Object { $_['VM Name'] }) -join ', ')
                        if ($index -lt 1 -or $index -gt 64) {
                            throw "VM '$vmNames': invalid network index in '$key' at line $lineNumber (expected 1..64)."
                        }
                        if ($seenNetworkKeys.ContainsKey($canonicalKey)) {
                            throw "VM '$vmNames': duplicate '$key' at line $lineNumber (previously defined at line $($seenNetworkKeys[$canonicalKey])). Check Network_N / VLAN_N numbering."
                        }
                        $seenNetworkKeys[$canonicalKey] = $lineNumber
                    }
                    $currentParams[$key] = $value
                }
                default {
                    throw "Found config key outside of a known block: $key"
                }
            }
        }
    }

    if ($currentVm) { $currentVmList += $currentVm }

    if ($currentVmList.Count -gt 0 -and $currentParams) {
        foreach ($vmItem in $currentVmList) {
            $sections += [pscustomobject]@{ VM = $vmItem; Params = $currentParams }
        }
    }

    foreach ($section in $sections) {
        foreach ($key in @($section.Params.Keys)) {
            if ($key -match '^VLAN_(\d+)$') {
                $networkKey = 'Network_' + $matches[1]
                if (-not $section.Params.ContainsKey($networkKey)) {
                    throw "VM '$($section.VM['VM Name'])': $key is defined but $networkKey is missing. Check Network_N / VLAN_N numbering."
                }
            }
        }
    }

    if (-not $sections -or $sections.Count -eq 0) {
        throw "No valid VM definition blocks were found in config file."
    }

    $sections
}

# Retrieves hVADComputer for the calling workflow.
function Get-HVADComputer {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ComputerName)
    Import-Module ActiveDirectory -ErrorAction Stop
    Get-ADComputer -Identity $ComputerName -ErrorAction SilentlyContinue
}

# Starts hVExecution Log for the calling workflow.
function Start-HVExecutionLog {
    param([Parameter(Mandatory = $true)][string]$ConfigFilePath,
          [Parameter(Mandatory = $true)][string]$LogDirectory,
          [switch]$StandardName)

    $fullPath   = (Resolve-Path -LiteralPath $ConfigFilePath -ErrorAction Stop).Path
    $configDir  = Split-Path -Path $fullPath -Parent
    $configLeaf = Split-Path -Path $fullPath -Leaf
    $baseName   = [System.IO.Path]::GetFileNameWithoutExtension($configLeaf)
    $baseName   = $baseName -replace '\.cfg$',''
    $stamp      = Get-Date -Format 'MMM_dd_HH-mm-ss'

    # Preserve the original Create filename format; use the shared log directory.
    $logDir = $LogDirectory
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    if ($StandardName) {
        $stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
        $candidate = Join-Path $logDir "Create_$stamp.log"
        $index = 1
        while (Test-Path -LiteralPath $candidate) {
            $candidate = Join-Path $logDir ("Create_{0}_{1}.log" -f $stamp,$index)
            $index++
        }
    }
    else {
        $candidate = Join-Path $logDir "$baseName._$stamp.log"
        $index = 1
        while (Test-Path -LiteralPath $candidate) {
            $candidate = Join-Path $logDir ("{0}._{1}_{2}.log" -f $baseName,$stamp,$index)
            $index++
        }
    }
    return $candidate
}

# Writes hVMessage for the calling workflow.
function Write-HVMessage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Message,[ConsoleColor]$ForegroundColor = [ConsoleColor]::Gray)
    Write-Host $Message -ForegroundColor $ForegroundColor
}

# Measures and reports optional execution timing without changing the workflow.
function Invoke-HVTiming {
    [CmdletBinding(DefaultParameterSetName='Action')]
    param(
        [Parameter(Mandatory=$true)][ValidateSet('Reset','Start','Stop','Measure','Report')][string]$Action,
        [Parameter(Mandatory=$false)][string]$TimingLabel,
        [string]$Target = '',
        [scriptblock]$ScriptBlock,
        [ValidateSet('OK','FAILED')][string]$Result = 'OK',
        [switch]$Enabled
    )
    # The context is reset at the beginning and cleared at the end of each command invocation.
    # Use a dedicated module-scoped context rather than the old global timing rows.
    if ($Action -eq 'Reset') {
        $script:HVTimingContext = @{
            Enabled = [bool]$Enabled
            Overall = [System.Diagnostics.Stopwatch]::StartNew()
            Rows = New-Object 'System.Collections.Generic.List[object]'
            Active = @{}
        }
        return
    }
    $ctx = $script:HVTimingContext
    if ($null -eq $ctx) {
        if ($Action -eq 'Measure') {
            if ($null -eq $ScriptBlock) { throw 'Measure requires -ScriptBlock.' }
            & $ScriptBlock
        }
        return
    }
    switch ($Action) {
        'Measure' {
            if ($null -eq $ScriptBlock) { throw 'Measure requires -ScriptBlock.' }
            if (-not $ctx.Enabled) { & $ScriptBlock; return }
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $outcome = 'OK'
            try { & $ScriptBlock }
            catch { $outcome = 'FAILED'; throw }
            finally {
                $sw.Stop()
                $row = [pscustomobject]@{Operation=$TimingLabel;Target=$Target;DurationMs=[math]::Round($sw.Elapsed.TotalMilliseconds,1);Result=$outcome}
                $ctx.Rows.Add($row) | Out-Null
                Write-Host ('[TIMING] {0} | {1} | {2:N1} ms | {3}' -f $TimingLabel,$Target,$row.DurationMs,$outcome)
            }
        }
        'Start' {
            if (-not $ctx.Enabled) { return }
            if (-not $TimingLabel) { throw 'Start requires -Name.' }
            $key = "$TimingLabel`n$Target"
            if ($ctx.Active.ContainsKey($key)) { throw "Timing operation already started: $TimingLabel ($Target)" }
            $ctx.Active[$key] = [System.Diagnostics.Stopwatch]::StartNew()
        }
        'Stop' {
            if (-not $ctx.Enabled) { return }
            $key = "$TimingLabel`n$Target"
            if (-not $ctx.Active.ContainsKey($key)) { throw "Timing operation was not started: $TimingLabel ($Target)" }
            $sw = $ctx.Active[$key]
            $sw.Stop()
            [void]$ctx.Active.Remove($key)
            $row = [pscustomobject]@{Operation=$TimingLabel;Target=$Target;DurationMs=[math]::Round($sw.Elapsed.TotalMilliseconds,1);Result=$Result}
            $ctx.Rows.Add($row) | Out-Null
            Write-Host ('[TIMING] {0} | {1} | {2:N1} ms | {3}' -f $TimingLabel,$Target,$row.DurationMs,$Result)
        }
        'Report' {
            try {
                $ctx.Overall.Stop()
                if ($ctx.Enabled) {
                    Write-Host "`n========== PERFORMANCE TIMING ==========" -ForegroundColor Cyan
                    # Summarize repetitive cluster parameter queries per target while
                    # retaining every individual [TIMING] event during execution.
                    $lookupGroups = @($ctx.Rows | Where-Object { $_.Operation -eq 'Cluster resource parameter lookup' } | Group-Object -Property Target)
                    $printedLookups = @{}
                    foreach ($r in $ctx.Rows) {
                        if ($r.Operation -eq 'Cluster resource parameter lookup') {
                            if ($printedLookups.ContainsKey([string]$r.Target)) { continue }
                            $printedLookups[[string]$r.Target] = $true
                            $group = @($lookupGroups | Where-Object { $_.Name -eq [string]$r.Target })[0]
                            $totalMs = ($group.Group | Measure-Object -Property DurationMs -Sum).Sum
                            $status = if (@($group.Group | Where-Object { $_.Result -ne 'OK' }).Count -gt 0) { 'FAILED' } else { 'OK' }
                            Write-Host ('{0,-38} {1,-22} {2,12:N1} ms  {3}' -f ('Cluster parameter lookups ({0} calls)' -f $group.Count),$r.Target,$totalMs,$status)
                            continue
                        }
                        Write-Host ('{0,-38} {1,-22} {2,12:N1} ms  {3}' -f $r.Operation,$r.Target,$r.DurationMs,$r.Result)
                    }
                    Write-Host ('Total elapsed (including prompts): {0:N2} s' -f $ctx.Overall.Elapsed.TotalSeconds)
                    Write-Host 'Note: nested measurements overlap; do not sum rows.'
                    Write-Host '========================================' -ForegroundColor Cyan
                }
            } finally {
                $script:HVTimingContext = $null
            }
        }
    }
}

# Reads hVConfig Guest Sections for the calling workflow.
function Read-HVConfigGuestSections {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Config file not found: $Path"
    }

    $lines = Get-Content -LiteralPath $Path
    $sections = @()
    $current = $null
    $currentNIC = $null

    foreach ($lineRaw in $lines) {
        $line = $lineRaw.TrimEnd()

        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        if ($line -match '^===') {
            if ($currentNIC) {
                $current.NetworkAdapters += $currentNIC
                $currentNIC = $null
            }

            if ($current) {
                $sections += $current
            }

            $current = @{
                General = @{}
                NetworkAdapters = @()
            }
            continue
        }

        if ($line -match '^\s*([^:]+)\s*:\s*(.*)$') {
            $k = $matches[1].Trim()
            $v = $matches[2].Trim()

            if ($k -eq "VM Net Adapter") {
                if ($currentNIC) {
                    $current.NetworkAdapters += $currentNIC
                }

                $currentNIC = @{
                    Name       = $v
                    IP         = $null
                    Mask       = $null
                    Gateway    = $null
                    DNS        = $null
                    Prefix     = $null
                    SwitchName = $null
                }
            }
            elseif ($k -eq "IP Address") {
                if ($currentNIC) { $currentNIC.IP = $v }
            }
            elseif ($k -eq "Subnet Mask") {
                if ($currentNIC) { $currentNIC.Mask = $v }
            }
            elseif ($k -eq "Default Gateway") {
                if ($currentNIC) { $currentNIC.Gateway = $v }
            }
            elseif ($k -eq "DNS Servers") {
                if ($currentNIC) { $currentNIC.DNS = $v }
            }
            else {
                if ($currentNIC) {
                    $current.NetworkAdapters += $currentNIC
                    $currentNIC = $null
                }

                $current.General[$k] = $v
            }
        }
    }

    if ($currentNIC) {
        $current.NetworkAdapters += $currentNIC
    }

    if ($current) {
        $sections += $current
    }

    return $sections
}

# Starts hVConfig Execution Log for the calling workflow.
function Start-HVConfigExecutionLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigFilePath
    )

    $scriptFolder = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($scriptFolder)) {
        $scriptFolder = (Get-Location).Path
    }

    $configLeaf = [System.IO.Path]::GetFileName($ConfigFilePath)

    if ($configLeaf -match '^(.*)\.cfg\.txt$') {
        $baseName = $matches[1]
    }
    else {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($configLeaf)
    }

    $logFolder = Join-Path $scriptFolder 'Logs'
    # Module wrapper provides the configured log directory on the jump host.
    # Remote node execution uses HVGC_LogPathOverride and is unchanged.
    if (-not [string]::IsNullOrWhiteSpace([string]$global:HVGC_ModuleLogDirectory)) {
        $logFolder = [string]$global:HVGC_ModuleLogDirectory
    }
    if (-not (Test-Path -LiteralPath $logFolder)) {
        New-Item -Path $logFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
    $stamp = Get-Date -Format 'MMM_dd_HH-mm-ss'
    return (Join-Path $logFolder ("{0}_{1}.log" -f $baseName, $stamp))
}

# Retrieves hVConfig ADComputer for the calling workflow.
function Get-HVConfigADComputer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ComputerName,
        [Parameter(Mandatory=$true)][string]$Domain,
        [Parameter(Mandatory=$true)][pscredential]$DomainCredential
    )
    $escapedComputerName = $ComputerName.Replace("'", "''")
    Get-ADComputer -Filter "Name -eq '$escapedComputerName'" -Server $Domain -Credential $DomainCredential -ErrorAction Stop
}

# Retrieves hVConfig Target Type for the calling workflow.
function Get-HVConfigTargetType {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Name)
    try {
        return Get-HVClusterProbe -Name $Name
    } catch {
        return [pscustomobject]@{ ClusterName = $null; Nodes = @($Name) }
    }
}
