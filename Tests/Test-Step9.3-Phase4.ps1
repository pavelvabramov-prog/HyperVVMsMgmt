$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'HyperVVMsMgmt.psd1') -Force
foreach ($alias in 'hv-create','hv-config','hv-remove','hv-creds') {
    if (-not (Get-Command $alias -ErrorAction SilentlyContinue)) { throw "Missing command: $alias" }
}
$remote = Join-Path $root 'CommandSpecific\Config\HVConfigShared.ps1'
$engine = Join-Path $root 'CommandSpecific\Config\GuestConfig-v2.5.ps1'
foreach ($path in @($remote,$engine)) {
    $tokens=$null; $errors=$null
    [System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors) | Out-Null
    if ($errors.Count) { throw "Syntax errors in $path : $($errors -join '; ')" }
}
. $remote
$cases = @(
    @{ VM='HVTSTVM034'; Names=@('HVTSTVM034'); Expected='Exact'; Confirm=$false },
    @{ VM='HVTSTVM034'; Names=@('HVTSTVM034 -Test v4.0'); Expected='SafeBoundary'; Confirm=$false },
    @{ VM='HVTSTVM034'; Names=@('HVTSTVM034 -A','HVTSTVM034 -B'); Expected='AmbiguousSafeBoundary'; Confirm=$true },
    @{ VM='HVTSTVM034'; Names=@('XXHVTSTVM034YY'); Expected='Questionable'; Confirm=$true },
    @{ VM='HVTSTVM034'; Names=@('XXHVTSTVM034YY','ZZHVTSTVM034QQ'); Expected='AmbiguousContains'; Confirm=$true }
)
foreach ($case in $cases) {
    $vms=@($case.Names | ForEach-Object { [pscustomobject]@{Name=$_} })
    $match=Find-HVVMMatches -ShortVMName $case.VM -VMs $vms
    if ($match.MatchType -ne $case.Expected -or $match.RequiresConfirmation -ne $case.Confirm) { throw "Matching regression: $($case.Expected)" }
}
try { Find-HVVMMatches -ShortVMName 'HVTSTVM034' -VMs @([pscustomobject]@{Name='DIFFERENT'}) | Out-Null; throw 'No-match did not throw' }
catch { if ($_.Exception.Message -eq 'No-match did not throw') { throw } }
$source = Get-Content -LiteralPath $engine -Raw
if ($source -notmatch 'Find-HVVMMatches -ShortVMName') { throw 'Config is not using shared matcher' }
if ($source -notmatch 'Write-HVMessage -Message') { throw 'Config is not using shared message writer' }
if ($source -notmatch 'Copy-Item -LiteralPath \$hvConfigSharedPath') { throw 'Remote helper packaging missing' }
# Create's original parameter set must remain present.
$createMatcher = Get-Content -LiteralPath (Join-Path $root 'Shared\Find-HVVMMatches.ps1') -Raw
if ($createMatcher -notmatch 'Get-VMNamesSafeLocal -NamePattern') { throw 'Create matcher changed' }
Write-Host 'PASS: exports, syntax, remote shared payload, Config matching categories, messaging and Create API preservation.' -ForegroundColor Green
Write-Host 'NOTE: Config parser, AD lookup, timing and logging remain compatibility implementations pending equivalence tests.'
Write-Host 'NOTE: Live Hyper-V ValidateOnly and Apply testing are not performed by this test.'
