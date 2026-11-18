$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$command = Get-Content (Join-Path $root 'Commands\Invoke-HVRemove.ps1') -Raw
$remote = Get-Content (Join-Path $root 'CommandSpecific\Remove\Invoke-RemovalEngine.ps1') -Raw
foreach ($term in @('Inspecting VM and storage','VM and storage inspection completed','Deleting VM and storage','VM and storage deletion stage completed')) { if (-not $command.Contains($term)) { throw "Missing progress text: $term" } }
foreach ($term in @('Connecting to Hyper-V node','Disconnecting from Hyper-V node','VM and storage inspection on remote node','VM and storage deletion on remote node')) { if (-not $remote.Contains($term)) { throw "Missing remote progress text: $term" } }
foreach ($p in @(Get-ChildItem $root -Recurse -File -Filter '*.ps1')) {
  $tokens=$null; $errors=$null
  [System.Management.Automation.Language.Parser]::ParseFile($p.FullName,[ref]$tokens,[ref]$errors) | Out-Null
  if ($errors.Count) { throw "Parse error: $($p.FullName): $($errors[0].Message)" }
}
Import-Module (Join-Path $root 'HyperVVMsMgmt.psd1') -Force
if (-not (Get-Command hv-remove).Parameters.ContainsKey('ShowTiming')) { throw '-ShowTiming missing' }
Write-Host 'PASS: Step 8.2.2 clear progress labels, optional timing, and syntax checks.' -ForegroundColor Green
