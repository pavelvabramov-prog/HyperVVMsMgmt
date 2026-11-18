$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'HyperVVMsMgmt.psd1') -Force
foreach ($cmd in 'hv-create','hv-config','hv-remove','hv-creds') { if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { throw "Missing $cmd" } }
$payload = Join-Path $root 'CommandSpecific\Config\HVConfigShared.ps1'
$engine = Join-Path $root 'CommandSpecific\Config\GuestConfig-v2.5.ps1'
foreach ($file in @($payload,$engine) + @(Get-ChildItem (Join-Path $root 'Shared') -Filter '*.ps1' | Select-Object -ExpandProperty FullName)) {
    $tokens=$null; $errors=$null
    [System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors) | Out-Null
    if ($errors.Count) { throw "Syntax failure in $file : $($errors -join '; ')" }
}
. $payload
foreach ($name in 'Read-HVConfigGuestSections','Start-HVConfigExecutionLog','Get-HVConfigADComputer','Get-HVConfigTargetType') { if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { throw "Missing payload helper: $name" } }
$tmp = Join-Path $env:TEMP ('hv-config-phase5-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    $config = Join-Path $tmp 'HVTSTVM034_OS_v3.0.cfg.txt'
    @'
====================
VM Name: HVTSTVM034
Hyper-V Host: HVTSTCLUSTER6
VM Net Adapter: Production
IP Address: 10.1.2.3
Subnet Mask: 255.255.255.0
Default Gateway: 10.1.2.1
DNS Servers: 10.1.2.2
'@ | Set-Content -LiteralPath $config
    $sections = @(Read-HVConfigGuestSections -Path $config)
    if ($sections.Count -ne 1 -or $sections[0].General['VM Name'] -ne 'HVTSTVM034' -or $sections[0].NetworkAdapters[0].IP -ne '10.1.2.3') { throw 'Guest config parser regression' }
    $global:HVGC_ModuleLogDirectory = $tmp
    $log = Start-HVConfigExecutionLog -ConfigFilePath $config
    if ((Split-Path $log -Parent) -ne $tmp -or (Split-Path $log -Leaf) -notmatch '^HVTSTVM034_OS_v3\.0_[A-Za-z]{3}_\d{2}_\d{2}-\d{2}-\d{2}\.log$') { throw "Log name regression: $log" }
    # Validate AD command argument compatibility using a function stub.
    function Get-ADComputer { param($Filter,$Server,$Credential,$ErrorAction) [pscustomobject]@{ Filter=$Filter; Server=$Server; Credential=$Credential } }
    $cred = New-Object pscredential('TEST	est',(ConvertTo-SecureString 'test' -AsPlainText -Force))
    $ad = Get-HVConfigADComputer -ComputerName "O'NEILL" -Domain 'example.test' -DomainCredential $cred
    if ($ad.Filter -ne "Name -eq 'O''NEILL'" -or $ad.Server -ne 'example.test' -or $ad.Credential -ne $cred) { throw 'AD lookup argument regression' }
    Remove-Item Function:\Get-ADComputer -ErrorAction SilentlyContinue
    $target = Get-HVConfigTargetType -Name 'nonexistent-test-host'
    if ($target.ClusterName -or @($target.Nodes).Count -ne 1 -or $target.Nodes[0] -ne 'nonexistent-test-host') { throw 'Standalone target regression' }
} finally {
    Remove-Variable HVGC_ModuleLogDirectory -Scope Global -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
$source = Get-Content -LiteralPath $engine -Raw
foreach ($call in 'Read-HVConfigGuestSections','Start-HVConfigExecutionLog','Get-HVConfigADComputer','Get-HVConfigTargetType') { if ($source -notmatch [regex]::Escape($call)) { throw "Config engine missing call: $call" } }
Write-Host 'PASS: exports, syntax, Config guest parser, log naming, AD lookup arguments, target fallback and remote payload.' -ForegroundColor Green
Write-Host 'NOTE: Timing remains unchanged; live Hyper-V ValidateOnly and Apply are not executed.'
