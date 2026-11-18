# Purpose: Test-HVVMNameVacancy - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Checks hVVMName Vacancy for the calling workflow.
function Test-HVVMNameVacancy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BaseVMName,
        [Parameter(Mandatory)][string]$TargetDisplayVMName,
        [Parameter(Mandatory)][object[]]$Inventory,
        [switch]$AllowDuplicateBaseVMName
    )
    $errors = @()
    $warnings = @()
    $nameMatches = @()
    $short = $BaseVMName.Trim()
    $display = $TargetDisplayVMName.Trim()
    foreach ($vm in @($Inventory)) {
        if ($null -eq $vm -or [string]::IsNullOrWhiteSpace([string]$vm.Name)) { continue }
        $name = ([string]$vm.Name).Trim()
        $kind = Get-HVVMNameClassification -ShortVMName $short -ExistingVMName $name
        if ($name -ieq $display) {
            $errors += "FullNameMatch: proposed full VM name '$display' already exists on '$($vm.Host)' (VM ID $($vm.Id)); override is not permitted."
        }
        if ($null -eq $kind) { continue }
        $nameMatches += [pscustomobject]@{ Name=$name; Kind='ShortNameMatch'; Host=$vm.Host; Id=$vm.Id; Path=$vm.Path }
        if (-not $AllowDuplicateBaseVMName) {
            $errors += "ShortNameMatch: existing VM '$name' contains '$short' on '$($vm.Host)' (VM ID $($vm.Id)); creation rejected. Use -AllowDuplicateBaseVMName only if intentional."
        } else {
            $warnings += "ShortNameMatch: '$name' on '$($vm.Host)' (VM ID $($vm.Id), path '$($vm.Path)'). Explicit Y/N/Q confirmation required before creation."
        }
    }
    [pscustomobject]@{ Errors=@($errors); Warnings=@($warnings); Matches=@($nameMatches) }
}
