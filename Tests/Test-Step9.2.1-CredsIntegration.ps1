$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$manifest = Join-Path $root 'HyperVVMsMgmt.psd1'
$parsed = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Commands\Invoke-HVCreds.ps1'), [ref]$parsed, [ref]$errors)
if ($errors.Count -gt 0) { throw ('Credential command syntax errors: ' + ($errors -join '; ')) }
Import-Module $manifest -Force
foreach ($aliasName in @('hv-create','hv-config','hv-remove','hv-creds')) {
    if (-not (Get-Command $aliasName -ErrorAction SilentlyContinue)) { throw "Missing command: $aliasName" }
}
if ((Get-Alias hv-creds).Definition -ne 'Invoke-HVCreds') { throw 'hv-creds alias points to unexpected function.' }
$source = Get-Content -LiteralPath (Join-Path $root 'Commands\Invoke-HVCreds.ps1') -Raw
foreach ($required in @('ValidateCredentials','Set-Variable -Name domainCred','-Scope Global')) {
    if (-not $source.Contains($required)) { throw "Missing expected credential behavior: $required" }
}
Write-Host 'PASS: hv-creds syntax, module exports, and credential validation wiring.' -ForegroundColor Green
Write-Host 'NOTE: Interactive AD validation must be tested on Windows with an authorized account.'
