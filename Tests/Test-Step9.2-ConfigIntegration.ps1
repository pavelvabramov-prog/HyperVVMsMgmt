# Step 9.2 static structural checks; no Hyper-V host needed.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$module = Join-Path $root 'HyperVVMsMgmt.psm1'
$manifest = Join-Path $root 'HyperVVMsMgmt.psd1'
$wrapper = Join-Path $root 'Commands\Invoke-HVConfig.ps1'
$engine = Join-Path $root 'CommandSpecific\Config\GuestConfig-v2.5.ps1'
foreach ($path in @($module,$manifest,$wrapper,$engine)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing: $path" }
    $tokens=$null; $errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
    if ($errors.Count -gt 0) { throw "Parse error in $path : $($errors[0])" }
}
Import-Module $manifest -Force -ErrorAction Stop
foreach ($name in @('hv-create','hv-remove','hv-config')) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { throw "Missing command: $name" }
}
$expected = @('ConfigFile','Help','ADCheckMode','ValidateOnly','AllowExistingADComputer','PSDirectMaxAttempts')
$actual = (Get-Command hv-config).Parameters.Keys
foreach ($name in $expected) { if ($name -notin $actual) { throw "Missing parameter: $name" } }
$engineText = [IO.File]::ReadAllText($engine)
if ($engineText -notmatch 'Copy-Item -LiteralPath \$PSCommandPath') { throw 'Remote source-copy mechanism not found' }
if ($engineText -notmatch 'GuestOnly is not supported yet') { throw 'GuestOnly safeguard missing' }
Write-Host 'PASS: module syntax, exports, Config parameters and remote source packaging.' -ForegroundColor Green
Write-Host 'NOTE: Does not execute remote Hyper-V/AD operations.' -ForegroundColor Yellow
