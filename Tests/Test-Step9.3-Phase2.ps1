$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'HyperVVMsMgmt.psd1') -Force
foreach ($alias in 'hv-create','hv-config','hv-remove','hv-creds') {
    if (-not (Get-Command $alias -ErrorAction SilentlyContinue)) { throw "Missing alias: $alias" }
}
$canonical = Get-Content -LiteralPath (Join-Path $root 'Shared\Convert-HVYesNo.ps1') -Raw
$bundle = Get-Content -LiteralPath (Join-Path $root 'CommandSpecific\Config\HVConfigShared.ps1') -Raw
if (-not $bundle.EndsWith($canonical)) { throw 'Remote shared helper differs from canonical shared function.' }
$engine = Get-Content -LiteralPath (Join-Path $root 'CommandSpecific\Config\GuestConfig-v2.5.ps1') -Raw
foreach ($fragment in @(". `$hvConfigSharedPath", "Copy-Item -LiteralPath `$hvConfigSharedPath", 'Convert-HVYesNo -Value')) {
    if (-not $engine.Contains($fragment)) { throw "Missing Config integration: $fragment" }
}
# Parse all new/modified scripts using Windows PowerShell parser (no execution).
foreach ($path in @('CommandSpecific\Config\GuestConfig-v2.5.ps1','CommandSpecific\Config\HVConfigShared.ps1')) {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $path), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "PowerShell parser errors in $path : $($errors | Out-String)" }
}
# Execute adapter in a separate script scope without triggering the engine.
. (Join-Path $root 'CommandSpecific\Config\HVConfigShared.ps1')
foreach ($case in @(@('Yes',$true),@('No',$false),@('On',$true),@('Off',$false),@('True',$true),@('False',$false))) {
    $value = Convert-HVYesNo -Value $case[0] -FieldName 'Test'
    if ($value -ne $case[1]) { throw "Unexpected conversion for $($case[0])" }
}
Write-Host 'PASS: four commands, remote shared payload, syntax and shared Yes/No conversion.' -ForegroundColor Green
Write-Host 'NOTE: Remote Hyper-V execution and guest configuration are not tested by this static test.'
