# Static regression guards for Hyper-V tag write safety; no VM changes.
$path = Join-Path $PSScriptRoot '..\CommandSpecific\Tags\TagTransports.ps1'
$source = Get-Content -LiteralPath $path -Raw
if ($source -match '(?s)Set-VM\s+`\s*\r?\n\s*-ComputerName') { throw 'Unsafe Set-VM -ComputerName parameter set detected.' }
foreach ($required in @('Get-VM -Id','Set-VM -VM $target -Notes $NotesToWrite -ErrorAction Stop','Tag write verification failed','Hyper-V tag update failed')) {
    if (-not $source.Contains($required)) { throw "Missing write safety guard: $required" }
}
Write-Host 'PASS: Hyper-V tag write parameter set, error propagation and readback guards.'
