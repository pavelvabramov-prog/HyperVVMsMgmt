# Purpose: Invoke-HVConfig - command entry point.
# Maintains the existing validation, logging, and execution behavior.

# Config command entry point: prepares the guest workflow for local or remote execution.
# Step 9.5: public Config command. Assembles private functions and workflow
# into a temporary self-contained script for jump-host and remote execution.
function Invoke-HVConfig {
    [CmdletBinding()]
    param(
        [string]$ConfigFile,
        [switch]$Help,
        [ValidateSet('JumpHostOnly','GuestOnly')]
        [string]$ADCheckMode = 'JumpHostOnly',
        [switch]$ValidateOnly,
        [switch]$StartVMIfOff,
        [switch]$AllowExistingADComputer,
        [ValidateRange(1,1000)]
        [int]$PSDirectMaxAttempts = 20
    )

    if ($Help) { Show-HVUsageHelp -Command Config; return }
    if ($StartVMIfOff -and -not $ValidateOnly) { throw "-StartVMIfOff requires -ValidateOnly." }

    # Build a self-contained, temporary execution script. The existing jump-host
    # dispatcher copies this same script to remote nodes; no module install needed.
    $configPrivateRoot = Join-Path $PSScriptRoot '..\CommandSpecific\Config'
    $configSharedRoot = Join-Path $PSScriptRoot '..\Shared'
    $workflowPath = Join-Path $configPrivateRoot 'ConfigWorkflow.ps1'
    $helperPath = Join-Path $configPrivateRoot 'HVConfigShared.ps1'
    $privateNames = @(
        'Show-UsageHelp','New-ConfigLogFilePath','Write-ReportField',
        'Convert-ToBoolFromYesNo','Convert-SubnetMaskToPrefixLength',
        'Get-DerivedComputerName','Get-TargetComputerName','Get-TargetDisplayVMName',
        'Test-ComputerNameBasic','Test-BaseVMNameFormat','Test-ErrorLooksLikeAuthFailure',
        'Test-ErrorLooksLikeNameOrConnectivityFailure','Test-ConfiguredHostMatchesLocalNode',
        'Get-SessionDomainCredential','Write-ExistingADComputerDomainJoinWarning',
        'Test-DomainMatchesLocalHostDomain','Invoke-HostSideAdDomainPrecheck',
        'Get-NormalizedDomainPrincipalNames',
        'Test-IPLooksVacant','Get-ReconnectCredentialCandidates',
        'Wait-GuestPsDirectReconnect','Invoke-PsDirectWithRetry',
        'Invoke-GuestSideTargetDomainPrecheck','Get-ConfigSections',
        'Resolve-VMTargetLocal','Show-VMTargetCandidates',
        'Get-GuestIPv4MatchLocal'
    )
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('HyperVConfig_' + [guid]::NewGuid().ToString('N'))
    $engine = Join-Path $tempDir 'GuestConfig.ps1'
    New-Item -Path $tempDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
    try {
        if (-not (Test-Path -LiteralPath $workflowPath -PathType Leaf)) { throw "Missing Config workflow: $workflowPath" }
        if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) { throw "Missing Config remote shared payload: $helperPath" }
        $source = New-Object System.Collections.Generic.List[string]
        $source.Add(@'
[CmdletBinding()]
param(
    [string]$ConfigFile,
    [switch]$Help,
    [ValidateSet('JumpHostOnly','GuestOnly')][string]$ADCheckMode = 'JumpHostOnly',
    [switch]$ValidateOnly,
    [switch]$StartVMIfOff,
    [switch]$AllowExistingADComputer,
    [ValidateRange(1,1000)][int]$PSDirectMaxAttempts = 20
)
'@)
        foreach ($name in $privateNames) {
            $file = Join-Path $configPrivateRoot ($name + '.ps1')
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing Config private function: $file" }
            $source.Add((Get-Content -LiteralPath $file -Raw -ErrorAction Stop))
        }
        # These reusable interactive helpers are canonical Shared definitions.
        # Include their source in the self-contained Config dispatcher so remote
        # execution does not depend on the module being installed on the node.
        foreach ($name in @('Select-VMTargetCandidate','Confirm-HVSelectedVMMatch')) {
            $file = Join-Path $configSharedRoot ($name + '.ps1')
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing shared Config selection helper: $file" }
            $source.Add((Get-Content -LiteralPath $file -Raw -ErrorAction Stop))
        }
        $source.Add((Get-Content -LiteralPath $workflowPath -Raw -ErrorAction Stop))
        [System.IO.File]::WriteAllText($engine, ($source -join "`r`n"), [System.Text.Encoding]::UTF8)
        Copy-Item -LiteralPath $helperPath -Destination (Join-Path $tempDir 'HVConfigShared.ps1') -ErrorAction Stop
        # Do not delete until the engine completes its local or remote dispatcher.

    # Forward exactly the supported public parameters. No global variables are
    # set by the wrapper; the v2.5 dispatcher manages its own remote context.
    $arguments = @{
        ADCheckMode = $ADCheckMode
        PSDirectMaxAttempts = $PSDirectMaxAttempts
    }
    if ($PSBoundParameters.ContainsKey('ConfigFile')) { $arguments.ConfigFile = $ConfigFile }
    if ($ValidateOnly) { $arguments.ValidateOnly = $true }
    if ($StartVMIfOff) { $arguments.StartVMIfOff = $true }
    if ($AllowExistingADComputer) { $arguments.AllowExistingADComputer = $true }

    # Centralized Config log directory, when present in the module settings.
    # The original engine retains its own log naming and remote transcript retrieval.
    $settings = Get-HVModuleConfiguration
    $logDir = if (-not [string]::IsNullOrWhiteSpace([string]$settings.ConfigLogPath)) { [string]$settings.ConfigLogPath } else { [string]$settings.LogPath }
    if (-not [System.IO.Path]::IsPathRooted($logDir)) { throw "Configured Config log directory must be absolute: $logDir" }
    $oldLogDir = Get-Variable -Name HVGC_ModuleLogDirectory -Scope Global -ErrorAction SilentlyContinue
    try {
        if ($logDir) { $global:HVGC_ModuleLogDirectory = $logDir }
        & $engine @arguments
    } finally {
        if ($oldLogDir) { Set-Variable -Name HVGC_ModuleLogDirectory -Scope Global -Value $oldLogDir.Value }
        else { Remove-Variable -Name HVGC_ModuleLogDirectory -Scope Global -ErrorAction SilentlyContinue }
    }
    } finally {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
