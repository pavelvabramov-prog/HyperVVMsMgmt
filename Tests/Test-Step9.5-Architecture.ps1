$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$expected = @('Invoke-HVCreate.ps1','Invoke-HVConfig.ps1','Invoke-HVRemove.ps1','Invoke-HVCreds.ps1','Invoke-HVTags.ps1','Invoke-HVInventory.ps1')
$actual = @(Get-ChildItem (Join-Path $root 'Commands') -Filter '*.ps1' | Select-Object -ExpandProperty Name)
if (@(Compare-Object $expected $actual).Count) { throw "Unexpected Commands files: $($actual -join ', ')" }
if (Test-Path (Join-Path $root 'CommandSpecific\Config\GuestConfig-v2.5.ps1')) { throw 'Legacy Config engine still present' }
if (-not (Test-Path (Join-Path $root 'CommandSpecific\Config\ConfigWorkflow.ps1'))) { throw 'Missing Config workflow' }
$privateFiles = @(Get-ChildItem (Join-Path $root 'CommandSpecific\Config') -Filter '*.ps1')
if ($privateFiles.Count -lt 29) { throw "Too few Config private files: $($privateFiles.Count)" }
foreach ($file in @(Get-ChildItem $root -Recurse -Filter '*.ps1') + @(Get-Item (Join-Path $root 'HyperVVMsMgmt.psm1'))) {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    if (@($errors).Count) { throw "Syntax errors in $($file.FullName): $($errors | Out-String)" }
}
Import-Module (Join-Path $root 'HyperVVMsMgmt.psd1') -Force
foreach ($name in 'hv-create','hv-config','hv-remove','hv-creds','hv-tags','hv-inventory') {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { throw "Missing command: $name" }
}
# Parse the actual self-contained Config source as the command assembles it.
$commandSource = Get-Content -LiteralPath (Join-Path $root 'Commands\Invoke-HVConfig.ps1') -Raw
$names = [regex]::Matches($commandSource, "'([A-Za-z][A-Za-z0-9-]+)'") |
    ForEach-Object { $_.Groups[1].Value } |
    Where-Object { Test-Path (Join-Path $root ("CommandSpecific\Config\$_.ps1")) } |
    Select-Object -Unique
$pieces = @('[CmdletBinding()]', 'param([string]$ConfigFile,[switch]$Help,[ValidateSet(''JumpHostOnly'',''GuestOnly'')][string]$ADCheckMode=''JumpHostOnly'',[switch]$ValidateOnly,[switch]$AllowExistingADComputer,[ValidateRange(1,1000)][int]$PSDirectMaxAttempts=20)')
foreach ($name in $names) {
    $pieces += Get-Content -LiteralPath (Join-Path $root ("CommandSpecific\Config\$name.ps1")) -Raw
}
foreach ($name in 'Select-VMTargetCandidate','Confirm-HVSelectedVMMatch') {
    $pieces += Get-Content -LiteralPath (Join-Path $root ("Shared\$name.ps1")) -Raw
}
$pieces += Get-Content -LiteralPath (Join-Path $root 'CommandSpecific\Config\ConfigWorkflow.ps1') -Raw
$tokens = $null; $errors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput(($pieces -join "`r`n"), [ref]$tokens, [ref]$errors)
if (@($errors).Count) { throw "Assembled Config script syntax error: $($errors | Out-String)" }
Write-Host 'PASS: unified Commands folder, private Config extraction, syntax and exports.' -ForegroundColor Green
Write-Host 'NOTE: Hyper-V runtime tests are required before Apply.' -ForegroundColor Yellow
