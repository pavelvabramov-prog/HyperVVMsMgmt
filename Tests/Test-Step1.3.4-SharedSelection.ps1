$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$moduleSource = Get-Content (Join-Path $root 'HyperVVMsMgmt.psm1') -Raw
$configSource = Get-Content (Join-Path $root 'Commands\Invoke-HVConfig.ps1') -Raw
$resolveSource = Get-Content (Join-Path $root 'Shared\Resolve-HVExistingVM.ps1') -Raw
foreach ($name in 'Select-VMTargetCandidate','Confirm-HVSelectedVMMatch') {
    $canonical = Join-Path $root ("Shared\$name.ps1")
    $old = Join-Path $root ("CommandSpecific\Config\$name.ps1")
    if (-not (Test-Path $canonical)) { throw "Missing canonical shared helper: $name" }
    if (Test-Path $old) { throw "Duplicate private helper remains: $name" }
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($canonical,[ref]$tokens,[ref]$errors)
    if (@($errors).Count) { throw "Invalid shared helper: $name" }
    $functions = @($ast.FindAll({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst]},$false))
    if ($functions.Count -ne 1 -or $functions[0].Name -ne $name) { throw "Unexpected function layout: $name" }
    if ($configSource -notmatch [regex]::Escape("'" + $name + "'")) { throw "Config dispatcher does not include shared helper: $name" }
    if ($resolveSource -notmatch [regex]::Escape($name)) { throw "Shared VM resolver no longer calls $name" }
}
if ($moduleSource.Contains("foreach (`$name in 'Select-VMTargetCandidate'")) { throw 'Legacy explicit Config helper loading remains' }
Import-Module (Join-Path $root 'HyperVVMsMgmt.psd1') -Force
$loaded = & (Get-Module HyperVVMsMgmt) { @(Get-Command Select-VMTargetCandidate,Confirm-HVSelectedVMMatch -CommandType Function -ErrorAction Stop) }
if (@($loaded).Count -ne 2) { throw 'Shared selection functions are not loaded' }
Write-Host 'PASS: shared selection/confirmation helpers and self-contained Config dispatch integration.' -ForegroundColor Green
