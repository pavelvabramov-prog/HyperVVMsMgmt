# Run after importing the v1.1.2-DEV module. Tests shared logic without Hyper-V.
$ErrorActionPreference = 'Stop'
$module = Get-Module HyperVVMsMgmt -ErrorAction Stop
& $module {
    $items = @(
        [pscustomobject]@{ Id='id-1';Name='NATSTVM040';Node='HOST1';Kind='ShortNameMatch';State='Off' },
        [pscustomobject]@{ Id='id-2';Name='NATSTVM040 - Test';Node='HOST2';Kind='ShortNameMatch';State='Off' }
    )
    $context = New-HVSelectionContext
    # Seed a previous selection without an interactive prompt.
    $context.Selected['id-1'] = $true
    $context.Excluded['id-2'] = $true
    $result = Resolve-HVBatchSelection -RequestedName 'NATSTVM040 - Test' -Candidates @($items[1]) -PermittedSelection Multiple -SelectionContext $context -ValidateOnly
    if ($result.Status -ne 'Skipped' -or $result.Reason -ne 'ExcludedByEarlierSelection') { throw 'Excluded candidate was not skipped.' }
    $new = [pscustomobject]@{Id='id-3';Name='NATSTVM040 - Testing';Node='HOST1';Kind='ShortNameMatch';State='Off'}
    $mixed = Resolve-HVBatchSelection -RequestedName 'NATSTVM040 - Test' -Candidates @($items[1],$new) -PermittedSelection Multiple -SelectionContext $context -ValidateOnly
    if ($mixed.Status -ne 'Skipped' -or $mixed.Reason -ne 'ExcludedByEarlierSelection') { throw 'Mixed excluded/unseen entry was not entirely skipped.' }
    $repeat = Resolve-HVBatchSelection -RequestedName 'NATSTVM040' -Candidates @($items[0]) -PermittedSelection Multiple -SelectionContext $context -ValidateOnly
    if ($repeat.Status -ne 'Skipped' -or $repeat.Reason -ne 'AlreadySelectedByEarlierEntry') { throw 'Previously selected GUID was not skipped.' }
    $fresh = New-HVSelectionContext
    if ($fresh.Selected.Count -ne 0 -or $fresh.Excluded.Count -ne 0) { throw 'Invocation state persisted.' }
    $auto = Resolve-HVBatchSelection -RequestedName 'NATSTVM041' -Candidates @($new) -PermittedSelection Single -SelectionContext $fresh -ValidateOnly
    if ($auto.Status -ne 'Selected' -or $auto.Selected.Count -ne 1) { throw 'Single unambiguous resolution failed.' }
    'PASS: v1.1.2 shared exclusion, overlap, duplicate and invocation-isolation tests.'
}
