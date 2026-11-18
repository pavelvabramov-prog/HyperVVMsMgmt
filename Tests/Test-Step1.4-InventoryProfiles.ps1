$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'CommandSpecific\Inventory\Read-HVInventoryReportProfiles.ps1')
$config = Join-Path $root 'Config\HyperVInventory.config.txt'
$p = Read-HVInventoryReportProfiles -Path $config
foreach ($name in @('Default','Short','Full')) { if (-not $p.Profiles.ContainsKey($name)) { throw "Missing $name" } }
if (@($p.Profiles['Full']).Count -ne 23) { throw 'Unexpected Full column count' }
if ($p.Profiles['Full'] -notcontains 'CheckpointSize, TB') { throw 'Checkpoint column missing' }
$source = Get-Content (Join-Path $root 'Commands\Invoke-HVInventory.ps1') -Raw
if ($source -notmatch '\$ReportProfile' -or $source -notmatch 'Read-HVInventoryReportProfiles') { throw 'Inventory command not profile-aware' }
$inventory = Get-Content (Join-Path $root 'CommandSpecific\Inventory\Get-HyperVVMInventory.ps1') -Raw
foreach ($category in @('Scope','Env','App','Role','Contact')) { if ($inventory -notmatch "'$category' =") { throw "Missing tag output $category" } }
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.txt')
try {
    @('[AVAILABLE COLUMNS]','VMName','[REPORT PROFILE: Default]','BadColumn') | Set-Content $tmp
    $caught = $false
    try { $null = Read-HVInventoryReportProfiles -Path $tmp } catch { $caught = $true }
    if (-not $caught) { throw 'Unknown column accepted' }
    @('[AVAILABLE COLUMNS]','VMName','[REPORT PROFILE: Default]','VMName','[REPORT PROFILE: default]','VMName') | Set-Content $tmp
    $caught = $false
    try { $null = Read-HVInventoryReportProfiles -Path $tmp } catch { $caught = $true }
    if (-not $caught) { throw 'Duplicate profile accepted' }
} finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
Write-Host 'PASS: inventory profile configuration, validation and tag integration.'
