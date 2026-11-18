# Mocked contract tests: no Hyper-V/cluster connectivity required.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'HyperVVMsMgmt.psd1') -Force
$module = Get-Module HyperVVMsMgmt
& $module {
    # Mock probe, keeping Config's legacy fallback behavior.
    function Get-HVClusterProbe { param($Name)
        if ($Name -eq 'CLUSTER') { return [pscustomobject]@{ClusterName='CLUSTER'; Nodes=@('NODE1','NODE2')} }
        throw 'cluster lookup failed'
    }
    $ok = Get-HVConfigTargetType -Name CLUSTER
    if ($ok.ClusterName -ne 'CLUSTER' -or @($ok.Nodes).Count -ne 2) { throw 'Config cluster probe failed' }
    $fallback = Get-HVConfigTargetType -Name HOST
    if ($null -ne $fallback.ClusterName -or @($fallback.Nodes).Count -ne 1 -or $fallback.Nodes[0] -ne 'HOST') { throw 'Config host fallback changed' }
}
# Verify placement calls canonical probe and retains null-on-failure behavior.
$placement = Get-Content (Join-Path $root 'Shared/Get-HVClusterPlacement.ps1') -Raw
if ($placement -notmatch 'Get-HVClusterProbe' -or $placement -notmatch 'Invoke-Command') { throw 'Placement is not using canonical remote probe' }
Write-Host 'PASS: canonical cluster probe, Config fallback and placement integration.' -ForegroundColor Green
