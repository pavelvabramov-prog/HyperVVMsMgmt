# Step 1.5.5: read-only parser and credential-guard regression tests.
$moduleRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $moduleRoot 'Shared\Read-HVVMConfig.ps1')
$sample = Join-Path $PSScriptRoot 'Example-Step1.5.5-ThreeVMs.cfg.txt'
$sections = @(Read-HVVMConfig -Path $sample)
if ($sections.Count -ne 3) { throw "Expected 3 VMs; found $($sections.Count)." }
$names = @($sections | ForEach-Object { $_.VM['VM Name'] })
if (($names -join ',') -ne 'HVTSTVM055,HVTSTVM056,HVTSTVM057') { throw 'Unexpected VM grouping.' }
if ($sections[0].Params['FolderNameOverride'] -or $sections[1].Params['FolderNameOverride']) { throw 'Shared group override should be empty.' }
if ($sections[2].Params['FolderNameOverride'] -ne 'HVTSTVM057_NEW') { throw 'Single-VM override missing.' }
$bad = (Get-Content -LiteralPath $sample -Raw) -replace '(?m)^(FolderNameOverride:)\s*$', '$1 SHARED_FOLDER'
$tmp = Join-Path $env:TEMP ('HVCreate_InvalidOverride_' + [guid]::NewGuid().ToString('N') + '.cfg.txt')
try {
    Set-Content -LiteralPath $tmp -Value $bad -Encoding UTF8
    $message = $null
    try { $null = @(Read-HVVMConfig -Path $tmp); throw 'Expected shared FolderNameOverride rejection.' }
    catch { $message = $_.Exception.Message }
    if ($message -notmatch 'SINGLE VM' -or $message -notmatch 'HVTSTVM055') { throw "Unexpected validation result: $message" }
} finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
$workflow = Get-Content -LiteralPath (Join-Path $moduleRoot 'CommandSpecific\Config\ConfigWorkflow.ps1') -Raw
if ($workflow -notmatch 'Run hv-creds in this PowerShell session') { throw 'Missing hv-config credential guidance.' }
Write-Host 'PASS: Three-VM grouping, FolderNameOverride restriction, and hv-config credential guidance.' -ForegroundColor Green
