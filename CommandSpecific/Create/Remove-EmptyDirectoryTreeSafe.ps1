# Purpose: Remove-EmptyDirectoryTreeSafe - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Removes empty Directory Tree Safe for the calling workflow.
function Remove-EmptyDirectoryTreeSafe {
        param(
            [Parameter(Mandatory = $true)][string]$Path,
            [Parameter(Mandatory = $true)][string]$ProtectedPath
        )

        if ([string]::IsNullOrWhiteSpace($Path)) { return }
        if (-not (Test-Path -LiteralPath $Path)) { return }

        $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
        $fullProtected = [System.IO.Path]::GetFullPath($ProtectedPath).TrimEnd('\')

        if ($fullPath.Equals($fullProtected, [System.StringComparison]::OrdinalIgnoreCase)) {
            return
        }

        # Remove only if there are no files anywhere under the folder.
        # This also removes a folder that contains only empty subfolders
        # such as "Virtual Machines", "Snapshots", or "Smart Paging".
        $fileCount = @(Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue).Count
        if ($fileCount -eq 0) {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path -LiteralPath $Path)) {
                Write-Host "Removed empty temporary display-name folder '$Path'" -ForegroundColor DarkGray
            }
        }
    }
