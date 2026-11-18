# PowerShell 5.1+; no Hyper-V connection required.
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Shared/ConvertTo-HVNormalizedTags.ps1')
$old = 'TAG_APP:ERP;TAG_CNT:Bob Bahd;TAG_ENV:TEST;TAG_SCP:BUS;TAG_WLD:DB'
$expectedOld = 'TAG_APP:ERP; TAG_CNT:Bob Bahd; TAG_ENV:TEST; TAG_SCP:BUS; TAG_WLD:DB'
if ((Format-HVReadableTags -Tags ($old -split ';')) -cne $expectedOld) { throw 'Legacy labels were changed or translated.' }
$new = @('Contact:Bob Bahd','Role:WEB','Role:DB','Env:TEST','Env:test','Scope:BUS','App:ERP')
$expected = 'Scope:BUS; Env:TEST; App:ERP; Role:DB; Role:WEB; Contact:Bob Bahd'
if ((Format-HVReadableTags -Tags $new) -cne $expected) { throw 'Standard ordering/deduplication failed.' }
if (Test-HVTagSetEqual -Left @('TAG_WLD:DB') -Right @('Role:DB')) { throw 'Legacy and new categories must be distinct.' }
$custom = Format-HVReadableTags -Tags @('Zeta:1','TAG_WLD:DB','Scope:BUS','Alpha:2')
if ($custom -cne 'Scope:BUS; Alpha:2; TAG_WLD:DB; Zeta:1') { throw "Unexpected custom ordering: $custom" }
Write-Host 'PASS: literal labels, standard order, custom order, deduplication and legacy preservation.'
