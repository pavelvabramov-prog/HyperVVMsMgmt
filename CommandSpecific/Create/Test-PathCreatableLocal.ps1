# Purpose: Test-PathCreatableLocal - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Checks path Creatable Local for the calling workflow.
function Test-PathCreatableLocal {
        param(
            [AllowNull()][string]$PathValue
        )

        if ([string]::IsNullOrWhiteSpace($PathValue)) { return $false }

        try {
            $candidate = $PathValue.Trim()
            while ($candidate.EndsWith('\') -or $candidate.EndsWith('/')) {
                $candidate = $candidate.Substring(0, $candidate.Length - 1)
            }
            if ([string]::IsNullOrWhiteSpace($candidate)) { return $false }

            $root = [System.IO.Path]::GetPathRoot($candidate)
            if ([string]::IsNullOrWhiteSpace($root)) { return $false }
            if (-not (Test-Path -LiteralPath $root)) { return $false }

            if ($candidate -match '^[Cc]:\\ClusterStorage\\([^\\/]+)(?:[\\/].*)?$') {
                $csvMount = "C:\ClusterStorage\$($matches[1])"
                if (-not (Test-Path -LiteralPath $csvMount)) { return $false }
            }

            $probe = $candidate
            while (-not [string]::IsNullOrWhiteSpace($probe)) {
                if (Test-Path -LiteralPath $probe) { return $true }
                $parent = Split-Path -Path $probe -Parent
                if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $probe) { break }
                $probe = $parent
            }

            return $true
        }
        catch { return $false }
    }
