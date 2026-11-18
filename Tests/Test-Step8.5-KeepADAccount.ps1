$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$cmd = Get-Content -LiteralPath (Join-Path $root 'Commands\Invoke-HVRemove.ps1') -Raw
$help = Get-Content -LiteralPath (Join-Path $root 'Shared\Show-HVUsageHelp.ps1') -Raw
$engine = Get-Content -LiteralPath (Join-Path $root 'CommandSpecific\Remove\Remove-NodeEngine.ps1') -Raw
foreach ($file in @(Get-ChildItem -LiteralPath $root -Filter '*.ps1' -Recurse)) {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if ($errors.Count) { throw "Parse error in $($file.FullName): $($errors[0])" }
}
foreach ($fragment in @('[switch]$KeepADAccount', '$KeepADAccount -and $ResetADAccount', "'Keep'", "'KEEP'", 'if ($KeepADAccount)', 'PRESERVED (unchanged by command)')) {
    if (-not $cmd.Contains($fragment)) { throw "Missing Remove feature: $fragment" }
}
if (-not $help.Contains('-KeepADAccount')) { throw 'Remove help lacks -KeepADAccount.' }
if (-not $engine.Contains('if ($ADHandledExternally)')) { throw 'Node-side AD guard missing.' }
Import-Module (Join-Path $root 'HyperVVMsMgmt.psd1') -Force
if (-not (Get-Command hv-remove).Parameters.ContainsKey('KeepADAccount')) { throw 'Public hv-remove lacks -KeepADAccount.' }
Write-Host 'PASS: Step 8.5 PowerShell source parses; KeepADAccount switch, conflict guard, help and node-side AD guard present.' -ForegroundColor Green
