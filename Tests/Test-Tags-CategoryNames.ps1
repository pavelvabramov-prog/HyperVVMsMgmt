# PowerShell 5.1+; no Hyper-V connection required.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'Shared/ConvertTo-HVNormalizedTags.ps1')
. (Join-Path $root 'Shared/Read-HVTagCatalog.ps1')
. (Join-Path $root 'CommandSpecific/Tags/Read-HVTagServerList.ps1')
$catalog = Read-HVTagCatalog -Path (Join-Path $root 'Config/ServerTags.config.txt')
foreach ($category in @('Scope','Env','App','Role','Contact')) { if (-not $catalog.ContainsKey($category)) { throw "Missing catalog category: $category" } }
$tags = @(Test-ApprovedTags -InputTags @('Scope:BUS','Env:TEST','App:ERP','Role:DB','Contact:Bob Bahd') -Catalog $catalog)
if ($tags.Count -ne 5) { throw 'New names were not accepted.' }
try { $null = @(Test-ApprovedTags -InputTags @('TAG_WLD:DB') -Catalog $catalog); throw 'Old category was unexpectedly approved.' } catch { if ($_.Exception.Message -match 'unexpectedly approved') { throw } }
$legacy = @(Test-ApprovedTags -InputTags @('TAG_WLD:DB') -Catalog $catalog -AllowLegacyForRemoval)
if ($legacy.Count -ne 1) { throw 'Legacy tag cannot be removed.' }
$temp = Join-Path $env:TEMP ('hv-tags-114-' + [guid]::NewGuid().ToString('N') + '.csv')
try {
    @('ServerName,TargetHost,Scope,Env,App,Role,Contact','TESTVM,PhysicalWindows,BUS,TEST,ERP,DB,Bob Bahd') | Set-Content -LiteralPath $temp
    $rows = @(Read-HVTagServerList -Path $temp -Catalog $catalog -Action Add)
    if ($rows.Count -ne 1 -or $rows[0].Tags.Count -ne 5) { throw 'CSV category names were not parsed.' }
} finally { Remove-Item -LiteralPath $temp -ErrorAction SilentlyContinue }
Write-Host 'PASS: catalog, command tag validation, legacy removal and CSV category names.'
