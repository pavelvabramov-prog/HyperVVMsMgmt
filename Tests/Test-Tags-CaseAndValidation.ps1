# Step 1.1.4.1: Windows PowerShell 5.1 compatible, no VM writes.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'Shared\ConvertTo-HVNormalizedTags.ps1')
. (Join-Path $root 'Shared\Read-HVTagCatalog.ps1')
$catalog = Read-HVTagCatalog -Path (Join-Path $root 'Config\ServerTags.config.txt')
$actual = @(Test-ApprovedTags -InputTags @('scope:bus','ENV:test','app:erp','role:db','contact:Bob Bahd') -Catalog $catalog)
$expected = 'Scope:BUS; Env:TEST; App:ERP; Role:DB; Contact:Bob Bahd'
if ((Format-HVReadableTags $actual) -cne $expected) { throw "Case mismatch: $(Format-HVReadableTags $actual)" }
$failed = $false
try { $null = Test-ApprovedTags -InputTags @('Scope:Bla-bla') -Catalog $catalog } catch { $failed = $true }
if (-not $failed) { throw 'Invalid value was not rejected by validator' }
Write-Host 'PASS: canonical category casing, approved values and rejection checks.'
