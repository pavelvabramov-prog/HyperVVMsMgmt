# HyperVVMsMgmt v1.1.0 - deterministic module loading and explicit public exports.
# Keep the existing Shared -> CommandSpecific -> Commands order.
$moduleRoot = $PSScriptRoot

$importHVModuleFile = {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required module file is missing: $Path"
    }
    try {
        # Treat load-time errors as terminating; do not expose a partial module.
        $ErrorActionPreference = 'Stop'
        . $Path
    }
    catch {
        throw "HyperVVMsMgmt failed to load '$Path': $($_.Exception.Message)"
    }
}

$sharedPath = Join-Path $moduleRoot 'Shared'
$commandSpecificPath = Join-Path $moduleRoot 'CommandSpecific'
foreach ($folder in @($sharedPath, $commandSpecificPath)) {
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
        throw "Required module directory is missing: $folder"
    }
}

Get-ChildItem -LiteralPath $sharedPath -Filter '*.ps1' -Recurse -File |
    Sort-Object FullName | ForEach-Object { . $importHVModuleFile -Path $_.FullName }
Get-ChildItem -LiteralPath $commandSpecificPath -Filter '*.ps1' -Recurse -File |
    Where-Object {
        $_.Name -notlike 'Node-*.ps1' -and
        $_.Name -ne 'Remove-NodeEngine.ps1' -and
        $_.FullName -notmatch '[\\/]CommandSpecific[\\/]Config[\\/]'
    } | Sort-Object FullName | ForEach-Object { . $importHVModuleFile -Path $_.FullName }

# Keep the original public function/alias mapping, including hv-creds.
$publicCommands = @(
    @{ Function = 'Invoke-HVCreate';    Alias = 'hv-create' }
    @{ Function = 'Invoke-HVRemove';    Alias = 'hv-remove' }
    @{ Function = 'Invoke-HVConfig';    Alias = 'hv-config' }
    @{ Function = 'Invoke-HVCreds';     Alias = 'hv-creds' }
    @{ Function = 'Invoke-HVTags';      Alias = 'hv-tags' }
    @{ Function = 'Invoke-HVInventory'; Alias = 'hv-inventory' }
)
foreach ($entry in $publicCommands) {
    $path = Join-Path $moduleRoot ("Commands/{0}.ps1" -f $entry.Function)
    . $importHVModuleFile -Path $path
    if (-not (Get-Command -Name $entry.Function -CommandType Function -ErrorAction SilentlyContinue)) {
        throw "Required public function was not defined by '$path': $($entry.Function)"
    }
    Set-Alias -Name $entry.Alias -Value $entry.Function -Scope Script -ErrorAction Stop
}
Export-ModuleMember -Function @($publicCommands | ForEach-Object { $_.Function }) `
                    -Alias @($publicCommands | ForEach-Object { $_.Alias })
