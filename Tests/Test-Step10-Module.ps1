[CmdletBinding()]
param([string]$ConfigFile, [string]$TargetHost, [switch]$RunValidateOnly)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$manifest = Join-Path $root 'HyperVVMsMgmt.psd1'
$files = @(Get-ChildItem -LiteralPath $root -Filter '*.ps1' -Recurse -File) + @(Get-Item (Join-Path $root 'HyperVVMsMgmt.psm1'))
foreach ($file in $files) {
    $tokens = $null; $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)
    if ($parseErrors.Count) { throw ("Parse errors in {0}: {1}" -f $file.FullName, ($parseErrors | Out-String)) }
}
Write-Host "PASS: Parsed $($files.Count) PowerShell files" -ForegroundColor Green
Test-ModuleManifest -Path $manifest | Out-Null
Import-Module $manifest -Force -ErrorAction Stop
Get-Command hv-create -ErrorAction Stop | Out-Null
Write-Host 'PASS: Module imported and hv-create discovered' -ForegroundColor Green
hv-create -Help
try { hv-create -ConfigFile 'DO_NOT_CREATE.cfg' -ErrorAction Stop; throw 'FAIL: Missing config did not fail' }
catch { if ($_.Exception.Message -notlike '*configuration file not found*') { throw }; Write-Host 'PASS: Missing config rejected' -ForegroundColor Green }
if ($RunValidateOnly) {
    if (-not $ConfigFile) { throw 'Specify -ConfigFile to run ValidateOnly.' }
    $args = @{ ConfigFile = $ConfigFile; ValidateOnly = $true }
    if ($TargetHost) { $args.TargetHost = $TargetHost }
    $configJson = Join-Path $root 'Config\HyperVTools.config.txt'
    if (-not (Test-Path -LiteralPath $configJson -PathType Leaf)) { throw "Copy existing HyperVTools.config.txt to $configJson before ValidateOnly." }
    hv-create @args
} else {
    Write-Host 'ValidateOnly not run. Supply -RunValidateOnly -ConfigFile <path> [-TargetHost <host>].' -ForegroundColor Yellow
}
