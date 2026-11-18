# Static regression checks; safe to run without Hyper-V or AD access.
$root = Split-Path $PSScriptRoot -Parent
$remove = Get-Content (Join-Path $root 'Commands\Invoke-HVRemove.ps1') -Raw
$parser = Get-Content (Join-Path $root 'CommandSpecific\Remove\Read-RemovalList.ps1') -Raw
$creds = Get-Content (Join-Path $root 'Commands\Invoke-HVCreds.ps1') -Raw
$help = Get-Content (Join-Path $root 'Shared\Show-HVUsageHelp.ps1') -Raw
$checks = @(
    @{ Name='Configured AD naming policy'; Pass=($remove.Contains('$settings.VMNaming.ShortNamePattern') -and $remove.Contains('[regex]::IsMatch($name')) },
    @{ Name='Per-row ADName propagated'; Pass=($remove.Contains('ADName=$request.ADName') -and $remove.Contains('$request.ADName')) },
    @{ Name='KeepADAccount accepted in list mode'; Pass=(-not $remove.Contains("'-KeepADAccount and -VMListFile cannot be used together")) },
    @{ Name='Optional third column parser'; Pass=($parser.Contains('ADName=') -and $parser.Contains('(?:\s+(\S+))?')) },
    @{ Name='Credentials help before prompting'; Pass=($creds.Contains('Show-HVUsageHelp -Command Creds; return')) },
    @{ Name='Credentials help text'; Pass=($help.Contains("'Creds' {") -and $help.Contains('hv-creds /?')) }
)
foreach ($check in $checks) {
    if (-not $check.Pass) { throw "FAIL: $($check.Name)" }
    Write-Host "PASS: $($check.Name)"
}
