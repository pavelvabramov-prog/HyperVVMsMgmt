# Static regression guards. Run integration tests on a Hyper-V host before Apply.
$root = Split-Path -Parent $PSScriptRoot
$remove = Get-Content -LiteralPath (Join-Path $root 'Commands\Invoke-HVRemove.ps1') -Raw
$tags = Get-Content -LiteralPath (Join-Path $root 'Commands\Invoke-HVTags.ps1') -Raw
$checks = @(
    ($remove -notmatch 'AD ACCOUNT VALIDATION'),
    ($remove -match 'may be used by any of the following Hyper-V VMs'),
    ($remove -match 'Are you sure you want to \$actionName AD account'),
    ($remove -match '\$adActionCompleted\.ContainsKey'),
    ($tags -match 'Input entries'),
    ($tags -match 'Selected targets'),
    ($tags -match 'Processing VM')
)
if ($checks -contains $false) { throw 'FAIL: v1.1.2 AD safety/tag reporting static guard.' }
Write-Host 'PASS: v1.1.2 AD safety and tag reporting static guards.' -ForegroundColor Green
