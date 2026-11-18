$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $root 'HyperVVMsMgmt.psd1'
Import-Module $modulePath -Force
foreach ($alias in 'hv-create','hv-config','hv-remove','hv-creds') {
    if (-not (Get-Command $alias -ErrorAction SilentlyContinue)) { throw "Missing alias: $alias" }
}
$helpText = (hv-config -Help 6>&1 | Out-String)
if ($helpText -notmatch 'hv-config -ConfigFile' -or $helpText -match 'GuestConfig-v2.5.ps1') {
    throw 'hv-config help did not use shared module help.'
}
$engine = Get-Content -LiteralPath (Join-Path $root 'CommandSpecific\Config\GuestConfig-v2.5.ps1') -Raw
if ($engine -notmatch 'HVGC_ModuleLogDirectory' -or $engine -notmatch 'HVGC_LogPathOverride') {
    throw 'Config logging compatibility hooks missing.'
}
$wrapper = Get-Content -LiteralPath (Join-Path $root 'Commands\Invoke-HVConfig.ps1') -Raw
if ($wrapper -notmatch 'Show-HVUsageHelp -Command Config' -or $wrapper -notmatch 'ConfigLogPath') {
    throw 'Shared help or configured logging integration missing.'
}
Write-Host 'PASS: four commands, shared Config help, Config log-directory handoff.' -ForegroundColor Green
Write-Host 'NOTE: No Hyper-V/AD operations performed. Guest engine and remote execution need runtime validation.'
