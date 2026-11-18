# Static regression checks; does not create VMs or change cluster roles.
[CmdletBinding()]
param([string]$ConfigFile, [string]$TargetHost, [switch]$RunValidateOnly)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'Test-Step10.3-Module.ps1') @PSBoundParameters
$commandSource = Get-Content -LiteralPath (Join-Path $root 'Commands\New-HVVM.ps1') -Raw
$helperSource = Get-Content -LiteralPath (Join-Path $root 'CommandSpecific\Create\Add-HVClusterVMRole.ps1') -Raw
if ($commandSource -match 'Invoke-Command -Session \$session[^\r\n]*roleDefinition' -or
    $commandSource -match '\$roleLookupDef' -or
    $commandSource -match '\$roleDefinition') {
    throw 'Remote cluster-role registration or verification code remains.'
}
if ($helperSource -notmatch 'Add-ClusterVirtualMachineRole -Cluster \$ClusterName -VirtualMachine \$VMName') {
    throw 'Expected jump-host cluster-role registration command was not found.'
}
if ($commandSource -notmatch 'Cluster role already exists') {
    throw 'Idempotent role check was not found.'
}
Write-Host 'PASS: Step 10.4 cluster registration is jump-host local and idempotent (static check).' -ForegroundColor Green
