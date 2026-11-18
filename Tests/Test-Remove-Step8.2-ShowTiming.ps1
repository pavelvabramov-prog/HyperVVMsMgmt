$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$commandText = [IO.File]::ReadAllText((Join-Path $root 'Commands\Invoke-HVRemove.ps1'))
$timingText = [IO.File]::ReadAllText((Join-Path $root 'Shared\Invoke-HVTiming.ps1'))
if ($commandText -notmatch '\[switch\]\$ShowTiming') { throw 'Public -ShowTiming missing' }
if ($commandText -notmatch 'Invoke-HVTiming -Action Reset -Enabled:\$ShowTiming') { throw 'Timing initialization missing' }
if ($commandText -notmatch 'Invoke-HVTiming -Action Report') { throw 'Timing report missing' }
if ($commandText -match 'HVRemoveTimingRows|Write-HVOperationTimingSummary|Measure-HVOperation') { throw 'Old Remove timing implementation remains' }
if ((Test-Path (Join-Path $root 'Shared\Measure-HVOperation.ps1')) -or (Test-Path (Join-Path $root 'Shared\Write-HVOperationTimingSummary.ps1'))) { throw 'Old timing helpers remain' }
foreach ($action in @('Reset','Start','Stop','Measure','Report')) {
    if ($timingText -notmatch "'$action'") { throw "Missing timing action $action" }
}
$paths = @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.ps1' | Select-Object -ExpandProperty FullName)
foreach ($path in $paths) {
    $tokens = $null; $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors) | Out-Null
    if ($errors.Count) { throw "Parser error in $path : $($errors[0].Message)" }
}
Import-Module (Join-Path $root 'HyperVVMsMgmt.psd1') -Force -ErrorAction Stop
if (-not (Get-Command hv-remove -ErrorAction SilentlyContinue)) { throw 'hv-remove missing' }
if (-not (Get-Command hv-create -ErrorAction SilentlyContinue)) { throw 'hv-create missing' }
$parameters = (Get-Command Invoke-HVRemove).Parameters
if (-not $parameters.ContainsKey('ShowTiming')) { throw '-ShowTiming is not exported' }
Write-Host 'PASS: Step 8.2 single shared timing function; optional -ShowTiming; no legacy timing helpers; PowerShell source parses.' -ForegroundColor Green
