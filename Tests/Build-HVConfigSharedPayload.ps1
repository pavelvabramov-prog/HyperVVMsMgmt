# Build-time only: assemble the Config remote payload from canonical Shared functions.
[CmdletBinding()]
param([switch]$VerifyOnly)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$target = Join-Path $root 'CommandSpecific\Config\HVConfigShared.ps1'
$names = @(
    'Convert-HVYesNo'
    'Test-HVShortVMName'
    'Get-HVDisplayVMName'
    'Get-HVVMNameClassification'
    'Find-HVVMMatches'
    'Get-HVClusterProbe'
    'Get-HVTargetType'
    'Read-HVVMConfig'
    'Get-HVADComputer'
    'Start-HVExecutionLog'
    'Write-HVMessage'
    'Invoke-HVTiming'
    'Read-HVConfigGuestSections'
    'Start-HVConfigExecutionLog'
    'Get-HVConfigADComputer'
    'Get-HVConfigTargetType'
)
$pieces = @('# AUTO-GENERATED from canonical Shared functions. Do not edit manually.', '# Regenerate with Tests/Build-HVConfigSharedPayload.ps1.')
foreach ($name in $names) {
    $matches = @()
    foreach ($file in @(Get-ChildItem (Join-Path $root 'Shared') -Filter '*.ps1' -Recurse -File)) {
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
        if (@($errors).Count) { throw "Cannot parse $($file.FullName)" }
        $matches += @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $false) | ForEach-Object { $_.Extent.Text.Trim() })
    }
    if ($matches.Count -ne 1) { throw "Expected one canonical Shared definition for $name, found $($matches.Count)" }
    $pieces += $matches[0]
}
$expected = ($pieces -join "`n`n") + "`n"
if ($VerifyOnly) {
    $actual = [System.IO.File]::ReadAllText($target, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF).Replace("`r`n", "`n")
    if ($actual -cne $expected) { throw 'Config remote payload differs from canonical Shared implementations. Run Build-HVConfigSharedPayload.ps1 to regenerate.' }
    Write-Host 'PASS: Config remote payload matches canonical Shared implementations.' -ForegroundColor Green
} else {
    [System.IO.File]::WriteAllText($target, $expected, (New-Object System.Text.UTF8Encoding($true)))
    Write-Host 'Generated Config remote payload from canonical Shared implementations.' -ForegroundColor Green
}
