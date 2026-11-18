# Run after installing the development module. Checks the shared display implementation.
$ErrorActionPreference = 'Stop'
$module = Get-Module HyperVVMsMgmt -ErrorAction Stop
$source = Get-Content -LiteralPath (Join-Path $module.ModuleBase 'Shared\Resolve-HVBatchSelection.ps1') -Raw
foreach ($token in @('Selection results:', 'SELECTED', 'EXCLUDED', 'already INCLUDED by earlier selection', 'already EXCLUDED by earlier selection', 'Skipping entry for', '$candidate.Name', '$hits.Count -gt 1')) {
    if (-not $source.Contains($token)) { throw "Selection summary missing expected token: $token" }
}
'PASS: v1.1.2 shared selection summary source checks.'
