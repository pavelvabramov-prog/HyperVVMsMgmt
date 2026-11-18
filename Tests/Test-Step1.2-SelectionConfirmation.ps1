# Step 1.2 non-runtime regression guards (Windows PowerShell 5.1 compatible).
$root = Split-Path $PSScriptRoot -Parent
$checks = @(
    @{File='Shared/Resolve-HVExistingVM.ps1'; Pattern='if (-not ($ValidateOnly -or $ReadOnly))'},
    @{File='CommandSpecific/Tags/TagTransports.ps1'; Pattern='-ReadOnly:($Action -eq ''Get'')'},
    @{File='CommandSpecific/Config/ConfigWorkflow.ps1'; Pattern='if (-not $ValidateOnly)'},
    @{File='Commands/Invoke-HVRemove.ps1'; Pattern='if (-not $ValidateOnly) {'}
)
foreach ($check in $checks) {
    $path = Join-Path $root $check.File
    $content = Get-Content -LiteralPath $path -Raw
    if (-not $content.Contains($check.Pattern)) { throw "FAIL: missing Step 1.2 guard in $($check.File): $($check.Pattern)" }
}
Write-Host 'PASS: Step 1.2 read-only/ValidateOnly confirmation guards (static checks).' -ForegroundColor Green

