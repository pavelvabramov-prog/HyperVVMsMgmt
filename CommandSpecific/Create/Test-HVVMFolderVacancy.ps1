# Purpose: Test-HVVMFolderVacancy - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Checks hVVMFolder Vacancy for the calling workflow.
function Test-HVVMFolderVacancy {
    param([Parameter(Mandatory = $true)][string]$Path)

    $errors = New-Object System.Collections.ArrayList
    try {
        if (Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction Stop) {
            [void]$errors.Add("VM destination folder is an existing file: $Path")
        }
        elseif (Test-Path -LiteralPath $Path -PathType Container -ErrorAction Stop) {
            # Stop after the first VM artifact. Enumerate filenames, not virtual disk contents.
            $match = Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction Stop |
                Where-Object { $_.Extension -in @('.vhd', '.vhdx', '.avhd', '.avhdx', '.vmcx', '.vmgs', '.vmwp', '.vmrs', '.vmsp', '.vsv', '.bin') -or
                    ($_.Extension -eq '.xml' -and $_.DirectoryName -match '(?i)[\\/]Virtual Machines(?:[\\/]|$)') } |
                Select-Object -First 1
            if ($null -ne $match) {
                [void]$errors.Add("VM destination folder contains existing Hyper-V files: $($match.FullName)")
            }
        }
    }
    catch {
        [void]$errors.Add("Cannot inspect VM destination folder '$Path': $($_.Exception.Message)")
    }
    return [pscustomobject]@{ Errors = $errors }
}
