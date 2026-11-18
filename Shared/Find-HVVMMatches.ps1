# Purpose: Find-HVVMMatches - shared helper.
# Maintains the existing validation, logging, and execution behavior.

# Finds potential VM matches before choosing a specific target.
function Find-HVVMMatches {
    [CmdletBinding(DefaultParameterSetName='Create')]
    param(
        [Parameter(Mandatory=$true,ParameterSetName='Create')][string]$NamePattern,
        [Parameter(ParameterSetName='Create')][switch]$Silent,
        [Parameter(Mandatory=$true,ParameterSetName='Config')][string]$ShortVMName,
        [Parameter(Mandatory=$true,ParameterSetName='Config')][object[]]$VMs
    )
    if ($PSCmdlet.ParameterSetName -eq 'Create') {
        # Preserve Create's original discovery behavior and error handling.
        @(Get-VMNamesSafeLocal -NamePattern $NamePattern -Silent:$Silent)
        return
    }
    # One case-insensitive literal ShortName match is selected automatically.
    $name = $ShortVMName.Trim()
    $seen = @{}
    $candidates = @()
    foreach ($vm in @($VMs)) {
        if ($null -eq $vm -or [string]::IsNullOrWhiteSpace([string]$vm.Name)) { continue }
        $display = ([string]$vm.Name).Trim()
        $kind = Get-HVVMNameClassification -ShortVMName $name -ExistingVMName $display
        if ($null -eq $kind) { continue }
        $identity = if ($null -ne $vm.PSObject.Properties['Id'] -and $null -ne $vm.Id) { [string]$vm.Id } else { $display.ToUpperInvariant() }
        if ($seen.ContainsKey($identity)) { continue }
        $seen[$identity] = $true
        $candidates += [pscustomobject]@{ VM = $vm; Kind = $kind }
    }
    if ($candidates.Count -eq 0) { throw "NoAnyMatches: No VM matched ShortName '$ShortVMName' on local host '$env:COMPUTERNAME'." }
    $allVMs = @($candidates | ForEach-Object { $_.VM })
    $kind = if ($candidates.Count -eq 1) { 'ShortNameMatch' } else { 'MultipleShortNameMatches' }
    return [pscustomobject]@{MatchType=$kind;RequiresConfirmation=($candidates.Count -gt 1);CurrentDisplayVMName=$(if($candidates.Count -eq 1){$allVMs[0].Name}else{$null});Candidates=$allVMs}
}
