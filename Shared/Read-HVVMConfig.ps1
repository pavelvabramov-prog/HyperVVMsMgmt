# Reads VM definitions and shared parameter groups from a Create configuration file.
# Each VM retains its own Tags; each group receives the following VM Parameters block.
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

        # A singular VM Name header starts the next VM in the same group;
        # the following VM Parameters block applies to every VM in that group.
        if ($trimmed -match '^=+\s*VM Name\s*=+$') {
            if ($currentVm) { $currentVmList += $currentVm; $currentVm = $null }
            $mode = 'VM'
            continue
        }

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

    # Group-level safeguard: a shared VM Parameters block cannot specify one folder override.
    # Group by parameter-block object identity, not by equal parameter values.
    $checkedParamBlocks = New-Object 'System.Collections.Generic.List[object]'
    foreach ($section in $sections) {
        $paramsBlock = $section.Params
        $alreadyChecked = $false
        foreach ($checked in $checkedParamBlocks) {
            if ([object]::ReferenceEquals($checked, $paramsBlock)) { $alreadyChecked = $true; break }
        }
        if ($alreadyChecked) { continue }
        [void]$checkedParamBlocks.Add($paramsBlock)

        $override = if ($paramsBlock.ContainsKey('FolderNameOverride')) { [string]$paramsBlock['FolderNameOverride'] } else { '' }
        if (-not [string]::IsNullOrWhiteSpace($override)) {
            $groupVMs = @($sections | Where-Object { [object]::ReferenceEquals($_.Params, $paramsBlock) })
            if ($groupVMs.Count -gt 1) {
                $names = @($groupVMs | ForEach-Object { [string]$_.VM['VM Name'] }) -join ', '
                throw ("FolderNameOverride '{0}' is allowed only for a SINGLE VM per VM Parameters section. This section applies to {1} VMs: {2}." -f $override.Trim(), $groupVMs.Count, $names)
            }
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


# Config compatibility implementation; canonical Create API above is preserved.
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

# ------------------------------------------------------------
# Local-only helpers
# ------------------------------------------------------------


# Config transcript naming and jump-host log-directory override.
