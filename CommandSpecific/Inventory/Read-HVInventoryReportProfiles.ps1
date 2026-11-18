# Purpose: Read-HVInventoryReportProfiles - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Reads hVInventory Report Profiles for the calling workflow.
function Read-HVInventoryReportProfiles {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Inventory report configuration not found: $Path" }
    $available = [System.Collections.Generic.List[string]]::new()
    $profiles = @{}
    $mode = ''
    $profileName = ''
    $lineNo = 0
    foreach ($raw in [System.IO.File]::ReadAllLines($Path)) {
        $lineNo++
        $line = ($raw -replace '\s+#.*$', '').Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        if ($line -ieq '[AVAILABLE COLUMNS]') { $mode = 'Available'; continue }
        if ($line -match '^\[REPORT PROFILE:\s*(.*?)\s*\]$') {
            $profileName = $Matches[1].Trim()
            if (-not $profileName) { throw "Empty report profile name at line $lineNo" }
            if ($profiles.ContainsKey($profileName)) { throw "Duplicate report profile '$profileName' at line $lineNo" }
            $profiles[$profileName] = [System.Collections.Generic.List[string]]::new()
            $mode = 'Profile'
            continue
        }
        if ($line.StartsWith('[')) { throw "Unknown inventory configuration section '$line' at line $lineNo" }
        if ($mode -eq 'Available') {
            if (@($available | Where-Object { $_ -ieq $line }).Count) { throw "Duplicate available column '$line' at line $lineNo" }
            [void]$available.Add($line)
        } elseif ($mode -eq 'Profile') {
            if (@($profiles[$profileName] | Where-Object { $_ -ieq $line }).Count) { throw "Duplicate column '$line' in report profile '$profileName' at line $lineNo" }
            [void]$profiles[$profileName].Add($line)
        } else { throw "Column '$line' outside a recognized section at line $lineNo" }
    }
    if (-not $available.Count) { throw 'Inventory configuration has no available columns.' }
    if (-not $profiles.ContainsKey('Default')) { throw 'Inventory configuration requires [REPORT PROFILE: Default].' }
    foreach ($name in @($profiles.Keys)) {
        if (-not $profiles[$name].Count) { throw "Report profile '$name' has no columns." }
        foreach ($column in $profiles[$name]) {
            if (-not @($available | Where-Object { $_ -ieq $column }).Count) { throw "Unknown column '$column' in report profile '$name'." }
        }
    }
    return [pscustomobject]@{ Available = @($available.ToArray()); Profiles = $profiles }
}
