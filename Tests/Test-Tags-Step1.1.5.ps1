#----------Step 1.1.5: Set vs ReplaceAll, parameter and help checks----------
$root = Split-Path -Parent $PSScriptRoot
$module = Join-Path $root 'HyperVVMsMgmt.psd1'
Import-Module $module -Force -ErrorAction Stop
$functionText = Get-Content (Join-Path $root 'Commands/Invoke-HVTags.ps1') -Raw
foreach ($switchName in @('Get','Add','Set','ReplaceAll','Remove','Clear')) {
    if ($functionText -notmatch ('\[switch\]\$' + $switchName)) { throw "Missing -$switchName switch" }
}
$transportText = Get-Content (Join-Path $root 'CommandSpecific/Tags/TagTransports.ps1') -Raw
if ($transportText -notmatch "'ReplaceAll'") { throw 'ReplaceAll action missing from transport' }
if ($transportText -notmatch 'requestedCategories') { throw 'Category-scoped Set logic missing' }
if ($functionText -match 'ValidateSet\(.Get.,.Add.') { throw 'Legacy -Action interface unexpectedly present' }
Write-Host 'PASS: Step 1.1.5 action switches and scoped Set/ReplaceAll static checks.'
