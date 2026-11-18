# Purpose: Start-HVExecutionLog - shared helper.
# Maintains the existing validation, logging, and execution behavior.

# Starts hVExecution Log for the calling workflow.
function Start-HVExecutionLog {
    param([Parameter(Mandatory = $true)][string]$ConfigFilePath,
          [Parameter(Mandatory = $true)][string]$LogDirectory,
          [switch]$StandardName)

    $fullPath   = (Resolve-Path -LiteralPath $ConfigFilePath -ErrorAction Stop).Path
    $configDir  = Split-Path -Path $fullPath -Parent
    $configLeaf = Split-Path -Path $fullPath -Leaf
    $baseName   = [System.IO.Path]::GetFileNameWithoutExtension($configLeaf)
    $baseName   = $baseName -replace '\.cfg$',''
    $stamp      = Get-Date -Format 'MMM_dd_HH-mm-ss'

    # Preserve the original Create filename format; use the shared log directory.
    $logDir = $LogDirectory
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    if ($StandardName) {
        $stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
        $candidate = Join-Path $logDir "Create_$stamp.log"
        $index = 1
        while (Test-Path -LiteralPath $candidate) {
            $candidate = Join-Path $logDir ("Create_{0}_{1}.log" -f $stamp,$index)
            $index++
        }
    }
    else {
        $candidate = Join-Path $logDir "$baseName._$stamp.log"
        $index = 1
        while (Test-Path -LiteralPath $candidate) {
            $candidate = Join-Path $logDir ("{0}._{1}_{2}.log" -f $baseName,$stamp,$index)
            $index++
        }
    }
    return $candidate
}


# Config compatibility implementation; canonical Create API above is preserved.
function Start-HVConfigExecutionLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigFilePath
    )

    $scriptFolder = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($scriptFolder)) {
        $scriptFolder = (Get-Location).Path
    }

    $configLeaf = [System.IO.Path]::GetFileName($ConfigFilePath)

    if ($configLeaf -match '^(.*)\.cfg\.txt$') {
        $baseName = $matches[1]
    }
    else {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($configLeaf)
    }

    $logFolder = Join-Path $scriptFolder 'Logs'
    # Module wrapper provides the configured log directory on the jump host.
    # Remote node execution uses HVGC_LogPathOverride and is unchanged.
    if (-not [string]::IsNullOrWhiteSpace([string]$global:HVGC_ModuleLogDirectory)) {
        $logFolder = [string]$global:HVGC_ModuleLogDirectory
    }
    if (-not (Test-Path -LiteralPath $logFolder)) {
        New-Item -Path $logFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
    $stamp = Get-Date -Format 'MMM_dd_HH-mm-ss'
    return (Join-Path $logFolder ("{0}_{1}.log" -f $baseName, $stamp))
}

# Config-specific domain-scoped lookup; does not change Create's identity-based AD lookup.
