$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'Shared/Read-HVVMConfig.ps1')
. (Join-Path $root 'Shared/ConvertTo-HVNormalizedTags.ps1')
. (Join-Path $root 'Shared/Read-HVTagCatalog.ps1')
. (Join-Path $root 'Shared/Get-HVTagsFromNotes.ps1')
. (Join-Path $root 'Shared/Set-HVTagsInNotes.ps1')
$sections = @(Read-HVVMConfig -Path (Join-Path $root 'Tests/Example-Step1.5-TwoVMs.cfg.txt'))
if ($sections.Count -ne 2) { throw 'Two-VM parser scope regression: expected exactly two VM sections' }
$firstName = [string]$sections[0].VM['VM Name']
$secondName = [string]$sections[1].VM['VM Name']
if ([string]::IsNullOrWhiteSpace($firstName) -or [string]::IsNullOrWhiteSpace($secondName) -or $firstName -eq $secondName) {
    throw 'Two-VM parser scope regression: VM names must be nonempty and distinct'
}
if ($sections[0].VM['Scope'] -ne 'IT' -or $sections[1].VM['Scope'] -ne 'IT' -or
    -not [string]::IsNullOrWhiteSpace([string]$sections[0].VM['Env']) -or $sections[1].VM['Env'] -ne 'INF') {
    throw 'Two-VM parser scope regression: Tags must remain scoped to their respective VM sections'
}
$cfg = Join-Path $root 'Config/ServerTags.config.txt'
$catalog = Read-HVTagCatalog -Path $cfg
$tags = @(Test-ApprovedTags -InputTags @('Scope:IT','Env:INF','Role:DB') -Catalog $catalog)
if ($tags.Count -ne 3) { throw 'Valid tag normalization failed' }
try { Test-ApprovedTags -InputTags @('Scope:INVALID') -Catalog $catalog | Out-Null; throw 'Expected validation failure' }
catch { if ($_.Exception.Message -match 'Expected validation failure') { throw } }
$notes = Set-TagsInNotes -Notes 'Original description' -NewTags $tags
if ($notes -notmatch 'Original description' -or @(Get-TagsFromNotes -Notes $notes).Count -ne 3) { throw 'Notes roundtrip failed' }
$create = Get-Content (Join-Path $root 'Commands/Invoke-HVCreate.ps1') -Raw
if ($create -notmatch 'Set-HVTagsForVMId' -or $create -notmatch 'Test-ApprovedTags' -or $create -notmatch 'CreateTags') { throw 'Create tag integration missing' }
if (Test-Path (Join-Path $root 'Shared/Tags')) { throw 'Shared/Tags must be flattened' }
if (-not (Test-Path (Join-Path $root 'Shared/Set-HVTagsForVMId.ps1'))) { throw 'Shared tag writer missing' }
Write-Host 'PASS: Step 1.5 tag validation, Notes roundtrip and shared Create integration.' -ForegroundColor Green
