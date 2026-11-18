#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs the HyperVVMsMgmt module for all Windows PowerShell users.
.DESCRIPTION
    Run this script from the extracted GitHub release ZIP. The script reads
    ModuleVersion from the adjacent HyperVVMsMgmt.psd1 manifest and installs
    the module into the matching versioned Windows PowerShell module folder.
    Existing versions are preserved; an installed version is never overwritten.
#>

$ErrorActionPreference = 'Stop'
$ModuleName = 'HyperVVMsMgmt'
$SourceRoot = $PSScriptRoot
$SourceManifest = Join-Path $SourceRoot "$ModuleName.psd1"

if (-not (Test-Path -LiteralPath $SourceManifest -PathType Leaf)) {
    throw "Cannot find $ModuleName.psd1 beside the installer. Extract the full release ZIP before running."
}

$ManifestData = Import-PowerShellDataFile -LiteralPath $SourceManifest
$Version = [version]$ManifestData.ModuleVersion
if (-not $Version -or $Version -le [version]'0.0') {
    throw 'The module manifest contains an invalid ModuleVersion.'
}

$RootModule = [string]$ManifestData.RootModule
if ([string]::IsNullOrWhiteSpace($RootModule) -or
    -not (Test-Path -LiteralPath (Join-Path $SourceRoot $RootModule) -PathType Leaf)) {
    throw "The module RootModule '$RootModule' is missing from the release package."
}

$ModuleBase = Join-Path $env:ProgramFiles "WindowsPowerShell\Modules\$ModuleName"
$Destination = Join-Path $ModuleBase $Version.ToString()
if (Test-Path -LiteralPath $Destination) {
    throw "Version $Version is already installed at '$Destination'. No files were changed."
}

# Stage files in the same parent directory to avoid leaving a partial version
# if copying fails. Move into place only after validating the staged manifest.
New-Item -ItemType Directory -Path $ModuleBase -Force | Out-Null
$Stage = Join-Path $ModuleBase ('.install-{0}' -f [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $Stage -ErrorAction Stop | Out-Null
    Get-ChildItem -LiteralPath $SourceRoot -Force |
        Where-Object { $_.Name -notin @('Install-HyperVVMsMgmt.ps1', 'Uninstall-HyperVVMsMgmt.ps1') } |
        Copy-Item -Destination $Stage -Recurse -Force -ErrorAction Stop

    $StagedManifest = Join-Path $Stage "$ModuleName.psd1"
    $null = Test-ModuleManifest -Path $StagedManifest -ErrorAction Stop

    if (Test-Path -LiteralPath $Destination) {
        throw "Destination '$Destination' appeared during installation. No overwrite attempted."
    }
    Move-Item -LiteralPath $Stage -Destination $Destination -ErrorAction Stop
}
finally {
    if (Test-Path -LiteralPath $Stage) {
        Remove-Item -LiteralPath $Stage -Recurse -Force
    }
}

Write-Host "Installed $ModuleName $Version successfully." -ForegroundColor Green
Write-Host "Location: $Destination"
Write-Host 'Installed versions:'
Get-ChildItem -LiteralPath $ModuleBase -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+(\.\d+){0,2}$' } |
    Sort-Object { [version]$_.Name } |
    ForEach-Object { Write-Host "  $($_.Name)" }
Write-Host "To load: Import-Module $ModuleName -RequiredVersion $Version"
