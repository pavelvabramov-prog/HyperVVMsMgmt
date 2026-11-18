# Runtime tests of file-order candidate priority (no Hyper-V or AD required).
$module = Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'HyperVVMsMgmt.psd1') -Force -PassThru
& $module {
    $items = @(
        [pscustomobject]@{Name='NATSTVM045TEST';Node='NANDEVH050';Id='a';Kind='ShortNameMatch'},
        [pscustomobject]@{Name='NATSTVM045EXTRA';Node='NANDEVH048';Id='b';Kind='ShortNameMatch'},
        [pscustomobject]@{Name='NATSTVM045';Node='NANDEVH050';Id='c';Kind='ShortNameMatch'}
    )
    $order = @(Sort-HVSelectionCandidates -Candidates $items -InputNames @('NATSTVM045','NATSTVM045TEST') -RequestedName 'NATSTVM045')
    if (($order.Name -join ',') -ne 'NATSTVM045,NATSTVM045TEST,NATSTVM045EXTRA') { throw 'Forward CSV order failed' }
    $reverse = @(Sort-HVSelectionCandidates -Candidates $items -InputNames @('NATSTVM045TEST','NATSTVM045') -RequestedName 'NATSTVM045TEST')
    if (($reverse.Name -join ',') -ne 'NATSTVM045TEST,NATSTVM045,NATSTVM045EXTRA') { throw 'Reverse CSV order failed' }
    $fallback = @(Sort-HVSelectionCandidates -Candidates $items -InputNames @() -RequestedName 'NATSTVM045')
    if ($fallback[0].Name -ne 'NATSTVM045') { throw 'Exact-name fallback failed' }
    Write-Host 'PASS: v1.1.2 candidate ordering (forward, reverse, exact fallback).' -ForegroundColor Green
}
