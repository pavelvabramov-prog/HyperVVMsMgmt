# Purpose: Read-HVTagServerList - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Reads hVTag Server List for the calling workflow.
function Read-HVTagServerList {
    param([Parameter(Mandatory)][string]$Path,[hashtable]$Catalog,[switch]$AllowCustomTags,[string]$Action)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Server list not found: $Path" }
    $lines = @(Get-Content -LiteralPath $Path -ErrorAction Stop)
    $data = [System.Collections.Generic.List[string]]::new()
    $numbers = [System.Collections.Generic.List[int]]::new()
    for ($i=0; $i -lt $lines.Count; $i++) {
        $trimmed = $lines[$i].Trim().TrimStart([char]0xFEFF)
        if (-not $trimmed -or $trimmed -match '^\s*(?:"\s*)?#') { continue }
        $data.Add($lines[$i]); $numbers.Add($i+1)
    }
    if ($data.Count -eq 0) { throw 'Server list contains no CSV header.' }
    $rows = @($data.ToArray() | ConvertFrom-Csv)
    $columns = @($data[0].Split(',') | ForEach-Object { $_.Trim().Trim('"') })
    $issues = [System.Collections.Generic.List[string]]::new()
    foreach ($needed in @('ServerName','TargetHost')) { if ($needed -notin $columns) { $issues.Add("Missing required column: $needed") } }
    $tagColumns = @($columns | Where-Object { $_ -notin @('ServerName','TargetHost') })
    if ($tagColumns.Count -eq 0) { $issues.Add('No tag category columns found') }
    foreach ($col in $tagColumns) {
        if (-not $Catalog.ContainsKey($col.ToUpperInvariant()) -and -not $AllowCustomTags) { $issues.Add("Unapproved CSV category column: $col") }
    }
    $seen = @{}
    $out = [System.Collections.Generic.List[object]]::new()
    for ($i=0; $i -lt $rows.Count; $i++) {
        $row = $rows[$i]
        $lineNo = $numbers[$i+1]
        $name = [string]$row.ServerName
        $target = [string]$row.TargetHost
        $name = $name.Trim(); $target = $target.Trim()
        if (-not $name) { $issues.Add("Row ${lineNo}: ServerName is empty") }
        if (-not $target) { $issues.Add("Row ${lineNo}: TargetHost is empty") }
        if ($name -and $seen.ContainsKey($name)) { $issues.Add("Row ${lineNo}: duplicate ServerName '$name' (first at row $($seen[$name]))") }
        if ($name) { $seen[$name] = $lineNo }
        $tags = [System.Collections.Generic.List[string]]::new()
        foreach ($col in $tagColumns) {
            foreach ($value in ([string]$row.$col -split ';')) {
                $value = $value.Trim()
                if ($value) { $tags.Add("${col}:$value") }
            }
        }
        $validationFailed = $false
        try { $validated = @(Test-ApprovedTags -InputTags $tags.ToArray() -Catalog $Catalog -AllowCustomTags:$AllowCustomTags) }
        catch { $issues.Add("Row ${lineNo}: $($_.Exception.Message)"); $validated = @(); $validationFailed = $true }
        if (-not $validationFailed -and $Action -in @('Add','Set','ReplaceAll','Remove') -and $validated.Count -eq 0) { $issues.Add("Row ${lineNo}: $Action with no tags is blocked; use Clear explicitly") }
        $out.Add([pscustomobject]@{ Row=$lineNo; ServerName=$name; TargetHost=$target; Tags=$validated })
    }
    if ($issues.Count) { throw "CSV preflight failed (no servers processed):`n - $($issues -join "`n - ")" }
    return @($out.ToArray())
}
