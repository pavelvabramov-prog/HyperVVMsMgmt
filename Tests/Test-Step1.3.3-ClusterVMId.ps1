$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'HyperVVMsMgmt.psd1') -Force
$m = Get-Module HyperVVMsMgmt
& $m {
    function Get-ClusterParameter { param($InputObject, $ErrorAction)
        if ($InputObject.Name -eq 'Missing') { return @() }
        if ($InputObject.Name -eq 'Broken') { throw 'parameter lookup failed' }
        [pscustomobject]@{ Name = 'VmId'; Value = '{E0A3BAC1-2C61-4ED1-8CEB-54F1D6A52D6A}' }
    }
    $id = Get-HVClusterResourceVMId -Resource ([pscustomobject]@{ Name = 'Present' })
    if ($id -cne 'e0a3bac1-2c61-4ed1-8ceb-54f1d6a52d6a') { throw 'VM GUID normalization failed' }
    $missing = Get-HVClusterResourceVMId -Resource ([pscustomobject]@{ Name = 'Missing' })
    if ($null -ne $missing) { throw 'Missing VmId must return null' }
    $failed = $false
    try { Get-HVClusterResourceVMId -Resource ([pscustomobject]@{ Name = 'Broken' }) -ErrorAction Stop | Out-Null } catch { $failed = $true }
    if (-not $failed) { throw 'Strict parameter lookup must fail closed' }
}
$inv = Get-Content (Join-Path $root 'CommandSpecific/Inventory/Get-HVInventoryClusterVMMap.ps1') -Raw
$rem = Get-Content (Join-Path $root 'CommandSpecific/Remove/Get-ClusterVMRoleById.ps1') -Raw
if ($inv -notmatch 'Get-HVClusterResourceVMId' -or $rem -notmatch 'Get-HVClusterResourceVMId') { throw 'Both callers must use canonical VmId extraction' }
Write-Host 'PASS: canonical cluster resource VmId lookup and both caller integrations.' -ForegroundColor Green
