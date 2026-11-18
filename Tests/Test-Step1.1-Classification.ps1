$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'HyperVVMsMgmt.psd1') -Force
$cases = @(
    @('HVTSTVM052','HVTSTVM052','ShortNameMatch'),
    @('HVTSTVM052','HVTSTVM052 - Production','ShortNameMatch'),
    @('HVTSTVM052','OLD-HVTSTVM052','ShortNameMatch'),
    @('HVTSTVM052','HVTSTVM052TEST','ShortNameMatch'),
    @('HVTSTVM052','OLDHVTSTVM052','ShortNameMatch'),
    @('HVTSTVM052','OTHER', $null)
)
foreach ($case in $cases) {
    $actual = & (Get-Module HyperVVMsMgmt) { param($short,$name) Get-HVVMNameClassification -ShortVMName $short -ExistingVMName $name } $case[0] $case[1]
    if ($actual -ne $case[2]) { throw "Classification mismatch for '$($case[1])': expected '$($case[2])', got '$actual'" }
}
Write-Host 'PASS: shared classification scenarios.' -ForegroundColor Green
