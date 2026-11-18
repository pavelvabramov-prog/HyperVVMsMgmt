# Static checks only; does not create or delete VMs.
$root = Split-Path -Parent $PSScriptRoot
$create = Get-Content (Join-Path $root 'Commands/Invoke-HVCreate.ps1') -Raw
$remove = Get-Content (Join-Path $root 'Commands/Invoke-HVRemove.ps1') -Raw
$timing = Get-Content (Join-Path $root 'Shared/Invoke-HVTiming.ps1') -Raw
if ($create -notmatch '\[switch\]\$ShowTiming') { throw 'Create -ShowTiming missing' }
if ($create -notmatch 'Invoke-HVTiming -Action Report') { throw 'Create timing report missing' }
if ($remove -notmatch 'VM and storage inspection total') { throw 'Remove label missing' }
if ($timing -notmatch 'Cluster parameter lookups') { throw 'Lookup aggregation missing' }
$bad = @()
Get-ChildItem $root -Filter '*.ps1' -Recurse | ForEach-Object {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { $bad += "${_}: $($errors[0].Message)" }
}
if ($bad.Count -gt 0) { throw ($bad -join "`n") }
Import-Module (Join-Path $root 'HyperVVMsMgmt.psd1') -Force
if (-not (Get-Command hv-create).Parameters.ContainsKey('ShowTiming')) { throw 'hv-create -ShowTiming not exported' }
if (-not (Get-Command hv-remove).Parameters.ContainsKey('ShowTiming')) { throw 'hv-remove -ShowTiming not exported' }
Write-Host 'PASS: Step 8.3 source parses, labels, aggregation, and both timing switches.' -ForegroundColor Green
