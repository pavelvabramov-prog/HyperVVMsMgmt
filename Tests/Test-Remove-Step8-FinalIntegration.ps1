$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$command = Join-Path $root 'Commands\Invoke-HVRemove.ps1'
$module = Join-Path $root 'HyperVVMsMgmt.psm1'
$removeDir = Join-Path $root 'CommandSpecific\Remove'
if (Test-Path (Join-Path $removeDir 'Invoke-HVRemoveLegacy.ps1')) { throw 'Legacy executable still present' }
$commandText = [IO.File]::ReadAllText($command)
if ($commandText -match 'Invoke-HVRemoveLegacy|&\s+\$legacy') { throw 'Legacy dependency in command' }
if ($commandText -notmatch 'function Invoke-HVRemove\s*\{') { throw 'Remove function missing' }
if ($commandText -notmatch 'Remove-NodeEngine.ps1.txt') { throw 'Node engine assembly missing' }
if ($commandText -notmatch 'Invoke-RemovalEngine') { throw 'Engine dispatch missing' }
if ($commandText -notmatch 'Remove-JumpHostADComputer') { throw 'AD cleanup missing' }
if ($commandText -notmatch 'Invoke-HVTiming') { throw 'Timing missing' }
$paths = @($command, $module) + @(Get-ChildItem -LiteralPath (Join-Path $root 'Shared') -Filter '*.ps1' -Recurse | Select-Object -ExpandProperty FullName) + @(Get-ChildItem -LiteralPath (Join-Path $root 'CommandSpecific') -Filter '*.ps1' -Recurse | Select-Object -ExpandProperty FullName)
foreach ($path in $paths) {
    $tokens = $null; $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors) | Out-Null
    if ($errors.Count) { throw "Parser error in $path : $($errors[0].Message)" }
}
$engine = [IO.File]::ReadAllText((Join-Path $removeDir 'Remove-NodeEngine.ps1.txt'))
$sets = @(
    @{Step=5;Names=@('Test-SafeBoundaryMatch','Resolve-VMBySafeBoundary','Get-ComputerNameFromVMDisplayName')},
    @{Step=6;Names=@('Get-ClusterVMInfo','Test-ClusterRoleGone','Get-ADComputerInfoSafe','Add-UniqueString','Get-VMDataInventory','Test-FileLocked')},
    @{Step=7;Names=@('Remove-ClusterRoleSafe','Wait-VMFileHandlesReleased','Remove-VMDataSafe')}
)
foreach ($set in $sets) {
    foreach ($name in $set.Names) {
        $path = Join-Path $removeDir "Node-$name.ps1.txt"
        if (-not (Test-Path -LiteralPath $path)) { throw "Missing node function: $name" }
        $source = [IO.File]::ReadAllText($path)
        $marker = if ($set.Step -eq 5) { '# HV_STEP5_NODE_ASSESSMENT_FUNCTIONS' } else { "# HV_STEP$($set.Step)_$name" }
        if (-not $engine.Contains($marker)) { throw "Missing marker: $marker" }
        if ($set.Step -eq 5) { $engine = $engine.Replace($marker, $source + "`r`n" + $marker) }
        else { $engine = $engine.Replace($marker, $source) }
    }
}
$engine = $engine.Replace('# HV_STEP5_NODE_ASSESSMENT_FUNCTIONS','')
$tokens = $null; $errors = $null
[System.Management.Automation.Language.Parser]::ParseInput($engine,[ref]$tokens,[ref]$errors) | Out-Null
if ($errors.Count) { throw "Assembled node engine parser error: $($errors[0].Message)" }
Import-Module (Join-Path $root 'HyperVVMsMgmt.psd1') -Force -ErrorAction Stop
if (-not (Get-Command hv-remove -ErrorAction SilentlyContinue)) { throw 'hv-remove missing' }
if (-not (Get-Command hv-create -ErrorAction SilentlyContinue)) { throw 'hv-create missing' }
Write-Host 'PASS: Step 8 native Remove command; no legacy executable; source and assembled node engine parse; both aliases exported.' -ForegroundColor Green
