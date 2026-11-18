[CmdletBinding()]
param([string]$ConfigFile, [string]$TargetHost, [switch]$RunValidateOnly)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$manifest = Join-Path $root 'HyperVVMsMgmt.psd1'
$files = @(Get-ChildItem -LiteralPath $root -Filter '*.ps1' -Recurse -File) + @(Get-Item (Join-Path $root 'HyperVVMsMgmt.psm1'))
foreach ($file in $files) {
    $tokens = $null; $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)
    if ($parseErrors.Count) { throw "Parse errors in $($file.FullName): $($parseErrors | Out-String)" }
}
Write-Host "PASS: Parsed $($files.Count) PowerShell files" -ForegroundColor Green
Test-ModuleManifest -Path $manifest | Out-Null
Import-Module $manifest -Force -ErrorAction Stop
$command = Get-Command hv-create -ErrorAction Stop
$actual = @($command.Parameters.Keys | Where-Object { $_ -in @('ConfigFile','TargetHost','ValidateOnly','AllowDuplicateBaseVMName','Help','Apply','RemainingArgs') })
$expected = @('ConfigFile','TargetHost','ValidateOnly','AllowDuplicateBaseVMName','Help')
if (@(Compare-Object $actual $expected).Count) { throw "Public parameter mismatch: $($actual -join ', ')" }
Write-Host 'PASS: Public parameters match approved Step 10.3 interface' -ForegroundColor Green
hv-create -Help
hv-create /?
Write-Host 'PASS: -Help and /? returned' -ForegroundColor Green
$functionFiles = @('Ensure-HVDirectory','Remove-EmptyDirectoryTreeSafe','Invoke-GrowVhdIfNeeded','Prepare-DiskPath','New-HVVMFromTemplate')
$source = ($functionFiles | ForEach-Object { Get-Content -LiteralPath (Join-Path $root "CommandSpecific\Create\$_.ps1") -Raw }) -join "`n"
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw "Remote function bundle has parse errors: $($errors | Out-String)" }
$topLevel = @($ast.EndBlock.Statements | Where-Object { $_ -isnot [System.Management.Automation.Language.FunctionDefinitionAst] })
if ($topLevel.Count) { throw 'Remote function bundle contains top-level executable statements.' }
Write-Host 'PASS: Remote Create function bundle parses as functions only' -ForegroundColor Green
if ($RunValidateOnly) {
    if (-not $ConfigFile) { throw 'Specify -ConfigFile to run ValidateOnly.' }
    $json = Join-Path $root 'Config\HyperVTools.config.txt'
    if (-not (Test-Path -LiteralPath $json -PathType Leaf)) { throw "Copy your existing TXT to $json" }
    $params = @{ ConfigFile=$ConfigFile; ValidateOnly=$true }
    if ($TargetHost) { $params.TargetHost = $TargetHost }
    hv-create @params
} else { Write-Host 'ValidateOnly not run. Use -RunValidateOnly on this test script only.' -ForegroundColor Yellow }
