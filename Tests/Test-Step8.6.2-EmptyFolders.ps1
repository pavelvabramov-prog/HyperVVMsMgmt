# Run in Windows PowerShell 5.1. Uses a temporary, disposable directory tree.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\CommandSpecific\Remove\Node-Remove-VMDataSafe.ps1')
$base = Join-Path $env:TEMP ('HV862_' + [guid]::NewGuid().ToString('N'))
$vm = Join-Path $base 'HVTSTVM033'
$child = Join-Path $vm 'Virtual Machines'
New-Item -ItemType Directory -Path $child -Force | Out-Null
try {
    $r = Remove-VMDataSafe -Folders @($vm,$child)
    if (Test-Path -LiteralPath $vm) { throw 'Expected VM folder to be removed' }
    if ($r.RemovedFolders.Count -ne 2) { throw "Expected 2 folders removed, got $($r.RemovedFolders.Count)" }
    if ($r.RemovedFolders[0] -ne $child) { throw 'Child folder was not removed first' }
    if (-not (Test-Path -LiteralPath $base)) { throw 'Shared parent was removed' }
    Write-Host 'PASS: empty child then parent removed; parent root preserved.' -ForegroundColor Green

    New-Item -ItemType Directory -Path $child -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $child 'keep.txt') -Value 'preserve'
    $r = Remove-VMDataSafe -Folders @($vm,$child)
    if (-not (Test-Path -LiteralPath (Join-Path $child 'keep.txt'))) { throw 'Nonempty folder content deleted' }
    if ($r.RemovedFolders.Count -ne 0) { throw 'Nonempty folder was removed' }
    Write-Host 'PASS: nonempty folders preserved.' -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
}
