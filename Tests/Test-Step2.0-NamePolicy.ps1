$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'HyperVVMsMgmt.psd1') -Force
$run = { param($short,$name) Get-HVVMNameClassification -ShortVMName $short -ExistingVMName $name }
foreach ($name in @('HVTSTVM085','HVTSTVM085 - Test','OLD-HVTSTVM085','OLDHVTSTVM085','HVTSTVM085OLD')) {
    $result = & (Get-Module HyperVVMsMgmt) $run 'HVTSTVM085' $name
    if ($result -ne 'ShortNameMatch') { throw "Expected ShortNameMatch for $name, got $result" }
}
$result = & (Get-Module HyperVVMsMgmt) $run 'HVTSTVM085' 'OTHER'
if ($null -ne $result) { throw 'Unexpected candidate match' }
$inventory = @([pscustomobject]@{Name='OLDHVTSTVM085';Host='TestNode';Id='1';Path='C:\Test'})
foreach ($allow in @($false,$true)) {
    $vacancy = & (Get-Module HyperVVMsMgmt) {param($v,$a) Test-HVVMNameVacancy -BaseVMName 'HVTSTVM085' -TargetDisplayVMName 'HVTSTVM085 - New' -Inventory $v -AllowDuplicateBaseVMName:$a } $inventory $allow
    if ($allow -and $vacancy.Errors.Count -ne 0) { throw 'Override should permit warning' }
    if (-not $allow -and $vacancy.Errors.Count -eq 0) { throw 'Default should reject any match' }
}
$full = @([pscustomobject]@{Name='HVTSTVM085 - New';Host='TestNode';Id='2';Path='C:\Test'})
$vacancy = & (Get-Module HyperVVMsMgmt) {param($v) Test-HVVMNameVacancy -BaseVMName 'HVTSTVM085' -TargetDisplayVMName 'HVTSTVM085 - New' -Inventory $v -AllowDuplicateBaseVMName } $full
if (-not @($vacancy.Errors | Where-Object {$_ -like 'FullNameMatch*'}).Count) { throw 'Exact FullName must reject even with override' }
Write-Host 'PASS: Step 2.0 ShortNameMatch / FullNameMatch checks.' -ForegroundColor Green
