# Read a whitespace-delimited VM removal list. The optional third column is an
# explicit AD account name. Two-column lists remain supported.
function Read-RemovalList {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "VM list file not found: $Path" }
    $entries = New-Object 'System.Collections.Generic.List[object]'
    $lineNumber = 0
    foreach ($line in (Get-Content -LiteralPath $Path -ErrorAction Stop)) {
        $lineNumber++
        $value = $line.Trim()
        if (-not $value -or $value.StartsWith('#')) { continue }
        if ($value -match '^(?i)VMName\s+TargetHost(?:\s+ADName)?\s*$') { continue }
        if ($value -match '^"([^"\r\n]+)"\s+(\S+)(?:\s+(\S+))?\s*$') {
            $name = $matches[1]; $hostName = $matches[2]; $adName = $matches[3]
        } elseif ($value -match '^(\S+)\s+(\S+)(?:\s+(\S+))?\s*$') {
            $name = $matches[1]; $hostName = $matches[2]; $adName = $matches[3]
        } else {
            throw "Invalid VM list entry at line ${lineNumber}: $value`nExpected: VMName TargetHost [ADName] (quote VM names containing spaces)."
        }
        if ($name -match '["\r\n]' -or $hostName -match '["\r\n]' -or $adName -match '["\r\n]') { throw "Invalid characters at line $lineNumber" }
        if ($adName -and ($adName -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,14}$' -or $adName -match '^[0-9]+$')) {
            throw "Invalid explicit ADName '$adName' at line $lineNumber (expected 1..15 letters/digits/hyphens)."
        }
        $entries.Add([pscustomobject]@{Name=$name.Trim();Host=$hostName.Trim();ADName=([string]$adName).Trim();Line=$lineNumber}) | Out-Null
    }
    return $entries.ToArray()
}
