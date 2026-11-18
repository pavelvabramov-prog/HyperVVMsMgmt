#Requires -Version 5.1
<#
.SYNOPSIS
    Lists or uninstalls versioned HyperVVMsMgmt installations.
.EXAMPLE
    .\Uninstall-HyperVVMsMgmt.ps1 -List
.EXAMPLE
    .\Uninstall-HyperVVMsMgmt.ps1 -Version 1.0.0
.EXAMPLE
    .\Uninstall-HyperVVMsMgmt.ps1 -All
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High', DefaultParameterSetName = 'List')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'List')]
    [switch]$List,

    [Parameter(Mandatory = $true, ParameterSetName = 'Version')]
    [ValidatePattern('^\d+\.\d+(\.\d+){0,2}$')]
    [string]$Version,

    [Parameter(Mandatory = $true, ParameterSetName = 'All')]
    [switch]$All
)

$ErrorActionPreference = 'Stop'
$ModuleName = 'HyperVVMsMgmt'
$ModuleBase = Join-Path $env:ProgramFiles "WindowsPowerShell\Modules\$ModuleName"

if (-not (Test-Path -LiteralPath $ModuleBase -PathType Container)) {
    Write-Host "$ModuleName is not installed at $ModuleBase"
    return
}

$Installed = @(Get-ChildItem -LiteralPath $ModuleBase -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+(\.\d+){0,2}$' -and
        (Test-Path -LiteralPath (Join-Path $_.FullName "$ModuleName.psd1") -PathType Leaf) } |
    Sort-Object { [version]$_.Name })

if ($PSCmdlet.ParameterSetName -eq 'List') {
    if ($Installed.Count -eq 0) { Write-Host 'No installed versions found.' }
    else { $Installed | Select-Object Name, FullName }
    return
}

# Listing is allowed without elevation; deletion from Program Files requires it.
$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run Windows PowerShell as Administrator to uninstall the module.'
}

if ($PSCmdlet.ParameterSetName -eq 'Version') {
    $Targets = @($Installed | Where-Object { [version]$_.Name -eq [version]$Version })
    if ($Targets.Count -eq 0) { throw "Version $Version is not installed." }
}
else {
    $Targets = @($Installed)
    if ($Targets.Count -eq 0) { Write-Host 'No installed versions found.'; return }
}

foreach ($Target in $Targets) {
    if ($PSCmdlet.ShouldProcess($Target.FullName, 'Remove installed module version')) {
        Remove-Module -Name $ModuleName -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $Target.FullName -Recurse -Force -ErrorAction Stop
        Write-Host "Removed $ModuleName $($Target.Name)"
    }
}

# Never delete unknown files or directories under the module's parent directory.
if ((Test-Path -LiteralPath $ModuleBase) -and
    @(Get-ChildItem -LiteralPath $ModuleBase -Force).Count -eq 0) {
    Remove-Item -LiteralPath $ModuleBase -Force
}
