# Static guard: hv-tags interactive Hyper-V mode must use the shared multi-VM
# resolver and process each selected GUID independently, without changing CSV mode.
$root = Split-Path -Parent $PSScriptRoot
$tags = Get-Content (Join-Path $root 'Commands\Invoke-HVTags.ps1') -Raw
$shared = Get-Content (Join-Path $root 'Shared\Resolve-HVExistingVM.ps1') -Raw
$required = @(
    'Resolve-HVExistingVM -VMName $ComputerName -HyperVHost $HyperVHost',
    '-PermittedSelection Multiple -SelectionContext $selectionContext',
    'foreach ($target in $resolvedTargets)',
    '-PreResolved $target',
    '-ReadOnly:($Action -eq ''Get'')'
)
foreach ($fragment in $required) {
    if (-not $tags.Contains($fragment)) { throw "Missing interactive multi-selection fragment: $fragment" }
}
if (-not $shared.Contains('foreach ($choice in @($selection.Selected))')) {
    throw 'Shared resolver no longer enumerates selected targets.'
}
if (-not $tags.Contains('-PermittedSelection Multiple -SelectionContext $selectionContext -ValidateOnly:$ValidateOnly')) {
    throw 'CSV shared multi-selection behavior was unexpectedly changed.'
}
Write-Host 'PASS: hv-tags interactive and CSV paths use shared multiple-selection targeting.'
