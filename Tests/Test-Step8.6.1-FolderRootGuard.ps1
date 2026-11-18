# Step 8.6.1 static regression: no malformed regex in folder root guard.
$ErrorActionPreference = 'Stop'
$source = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\CommandSpecific\Remove\Node-Remove-VMDataSafe.ps1') -Raw
if ($source -notmatch '\[System\.IO\.Path\]::GetPathRoot') { throw 'Filesystem root guard missing' }
if ($source -notmatch '\$isRoot') { throw 'Root comparison missing' }
if ($source.Contains('Unterminated [] set')) { throw 'Unexpected malformed regex marker' }
Write-Host 'PASS: Step 8.6.1 folder root guard is present.' -ForegroundColor Green
