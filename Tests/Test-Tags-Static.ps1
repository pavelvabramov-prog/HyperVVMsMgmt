# Safe smoke checks: no infrastructure connections.
Import-Module (Join-Path $PSScriptRoot '..\HyperVVMsMgmt.psd1') -Force -ErrorAction Stop
if (-not (Get-Command hv-tags -ErrorAction SilentlyContinue)) { throw 'hv-tags alias missing' }
hv-tags -Help
hv-tags -ListTags
Write-Host 'Tags smoke checks passed.'
