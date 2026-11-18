# Static regression checks; no Hyper-V connection required.
$root = Split-Path $PSScriptRoot -Parent
$shared = Get-Content (Join-Path $root 'Shared/ConvertTo-HVNormalizedTags.ps1') -Raw
$transport = Get-Content (Join-Path $root 'CommandSpecific/Tags/TagTransports.ps1') -Raw
foreach ($fn in 'ConvertTo-HVOrderedTags','Format-HVReadableTags','Test-HVTagSetEqual') {
    if ($shared -notmatch ('function\s+' + [regex]::Escape($fn) + '\b')) { throw "Missing helper: $fn" }
}
if ($shared -match 'ConvertTo-HVCanonicalTag|Sort-Object\s+-Stable') { throw 'Legacy alias translation or PS7-only sorting remains.' }
if ($transport -notmatch 'Format-HVReadableTags -Tags \$NewTags') { throw 'Hyper-V Notes writer must use literal formatting.' }
if ($shared -notmatch 'ErrorActionPreference') { throw 'Normalization must fail closed.' }
Write-Host 'PASS: literal tag format integration and PS 5.1 static checks.'
