# Purpose: Get-VmNameHintsFromPath - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Retrieves vm Name Hints From Path for the calling workflow.
function Get-VmNameHintsFromPath {
    param(
        [AllowNull()][string]$PathValue,
        [Parameter(Mandatory = $true)][string]$BaseVMName
    )

    $hints = New-Object System.Collections.ArrayList
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return @() }

    try {
        $diskPath   = $PathValue.Trim()
        $parentPath = Split-Path -Path $diskPath -Parent
        $parentLeaf = if (-not [string]::IsNullOrWhiteSpace($parentPath)) { Split-Path -Path $parentPath -Leaf } else { $null }
        $fileBase   = [System.IO.Path]::GetFileNameWithoutExtension($diskPath)

        foreach ($candidate in @($parentLeaf, $fileBase)) {
            if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
            if ($candidate -match '^([A-Za-z0-9]{10})') {
                $hint = $matches[1].ToUpper()
                if ($hint -ne $BaseVMName.ToUpper() -and -not $hints.Contains($hint)) {
                    [void]$hints.Add($hint)
                }
            }
        }
    }
    catch {
    }

    return @($hints)
}
