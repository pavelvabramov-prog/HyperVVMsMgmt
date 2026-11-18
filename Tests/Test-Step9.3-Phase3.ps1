$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'HyperVVMsMgmt.psd1') -Force
foreach ($alias in 'hv-create','hv-config','hv-remove','hv-creds') {
    if (-not (Get-Command $alias -ErrorAction SilentlyContinue)) { throw "Missing alias: $alias" }
}
$bundle = Get-Content -LiteralPath (Join-Path $root 'CommandSpecific\Config\HVConfigShared.ps1') -Raw
foreach ($name in 'Convert-HVYesNo','Test-HVShortVMName','Get-HVDisplayVMName') {
    $canonical = Get-Content -LiteralPath (Join-Path $root "Shared\$name.ps1") -Raw
    if (-not $bundle.Contains($canonical.TrimStart([char]0xFEFF).TrimEnd())) { throw "Remote bundle differs from Shared/$name.ps1" }
}
$engine = Get-Content -LiteralPath (Join-Path $root 'CommandSpecific\Config\GuestConfig-v2.5.ps1') -Raw
foreach ($fragment in @('Test-HVShortVMName -BaseVMName $Name', 'Get-HVDisplayVMName -BaseVMName $BaseVMName', 'Copy-Item -LiteralPath $hvConfigSharedPath')) {
    if (-not $engine.Contains($fragment)) { throw "Missing integration: $fragment" }
}
foreach ($path in @('CommandSpecific\Config\GuestConfig-v2.5.ps1','CommandSpecific\Config\HVConfigShared.ps1','Shared\Test-HVShortVMName.ps1','Shared\Get-HVDisplayVMName.ps1')) {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $path), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "Parser errors in $path : $($errors | Out-String)" }
}
. (Join-Path $root 'CommandSpecific\Config\HVConfigShared.ps1')
Test-HVShortVMName -BaseVMName 'HVTSTVM034' -Pattern '^[A-Za-z0-9]{10}$' -Context 'Config section'
$failed = $false
try { Test-HVShortVMName -BaseVMName 'INVALID' -Pattern '^[A-Za-z0-9]{10}$' -Context 'Config section' } catch { $failed = $true }
if (-not $failed) { throw 'Invalid short VM name accepted' }
if ((Get-HVDisplayVMName -BaseVMName 'HVTSTVM034' -VMDescription 'Test v4.0' -ConfigDescriptionStyle) -ne 'HVTSTVM034 - Test v4.0') { throw 'Config display name mismatch' }
if ((Get-HVDisplayVMName -BaseVMName 'HVTSTVM034' -VMDescription '-Test v4.0') -ne 'HVTSTVM034 -Test v4.0') { throw 'Create display name regression' }
Write-Host 'PASS: commands, canonical remote payload, Config short-name and display-name adapters, syntax.' -ForegroundColor Green
Write-Host 'NOTE: VM discovery and target type are not migrated; their current Shared implementations are Create-specific.'
Write-Host 'NOTE: Hyper-V/AD runtime validation is still required.'
