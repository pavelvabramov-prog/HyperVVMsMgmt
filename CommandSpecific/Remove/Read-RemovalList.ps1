# Purpose: Read-RemovalList - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Reads removal List for the calling workflow.
function Read-RemovalList {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "VM list file not found: $Path" }
    $entries = New-Object 'System.Collections.Generic.List[object]'
    $lineNumber = 0
    foreach ($line in (Get-Content -LiteralPath $Path -ErrorAction Stop)) {
        $lineNumber++
        $value = $line.Trim()
        if (-not $value -or $value.StartsWith('#')) { continue }
        if ($value -match '^(?i)VMName\s+TargetHost\s*$') { continue }
        if ($value -match '^"([^"]+)"\s+(\S+)\s*$') {
            $name = $matches[1]; $hostName = $matches[2]
        } elseif ($value -match '^(\S+)\s+(\S+)\s*$') {
            $name = $matches[1]; $hostName = $matches[2]
        } else { throw "Invalid VM list entry at line ${lineNumber}: $value`nExpected: VMName TargetHost (quote VM names containing spaces)." }
        if ($name -match '["\r\n]' -or $hostName -match '["\r\n]') { throw "Invalid characters at line $lineNumber" }
        $entries.Add([pscustomobject]@{Name=$name.Trim();Host=$hostName.Trim();Line=$lineNumber}) | Out-Null
    }
    return $entries.ToArray()
}
