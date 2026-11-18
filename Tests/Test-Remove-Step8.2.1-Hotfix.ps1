$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$helper=Get-Content (Join-Path $root 'Shared\Invoke-HVTiming.ps1') -Raw
if ($helper -match '\$Name\b') { throw 'Timing helper still shadows caller VM name' }
if ($helper -notmatch '\$TimingLabel') { throw 'Missing timing-only label parameter' }
$source=Get-Content (Join-Path $root 'CommandSpecific\Remove\Invoke-RemovalEngine.ps1') -Raw
if ($source -notmatch 'VM and storage inspection') { throw 'Missing friendly label' }
foreach($f in (Get-ChildItem $root -Recurse -Filter '*.ps1' -File)) {
 $tokens=$null;$errors=$null
 [System.Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$tokens,[ref]$errors)|Out-Null
 if($errors.Count) { throw "Parse error: $($f.FullName): $($errors[0].Message)" }
}
Import-Module (Join-Path $root 'HyperVVMsMgmt.psd1') -Force
Write-Host 'PASS: Step 8.2.1 timing label no longer shadows VM name; source parses.' -ForegroundColor Green
