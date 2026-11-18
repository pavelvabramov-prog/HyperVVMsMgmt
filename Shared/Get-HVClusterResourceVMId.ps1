# Canonical cluster-resource VmId extraction used by Inventory and Remove.
# Returns a normalized GUID string, or $null when no VmId parameter exists.
# Callers retain their own enumeration, timing, warning and fail-closed policies.
function Get-HVClusterResourceVMId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]$Resource,
        [switch]$IgnoreParameterErrors,
        [string]$TimingTarget
    )
    process {
        if ($IgnoreParameterErrors) {
            $parameters = @(Get-ClusterParameter -InputObject $Resource -ErrorAction SilentlyContinue)
        } elseif (-not [string]::IsNullOrWhiteSpace($TimingTarget)) {
            $parameters = @(Invoke-HVTiming -Action Measure -TimingLabel 'Cluster resource parameter lookup' -Target $TimingTarget -ScriptBlock {
                Get-ClusterParameter -InputObject $Resource -ErrorAction Stop
            })
        } else {
            $parameters = @(Get-ClusterParameter -InputObject $Resource -ErrorAction Stop)
        }
        $match = @($parameters | Where-Object { $_.Name -ieq 'VmId' } | Select-Object -First 1)
        if (-not $match.Count -or $null -eq $match[0].Value) { return }
        $value = ([string]$match[0].Value).Trim().Trim('{}')
        $parsed = [guid]::Empty
        if ([guid]::TryParse($value, [ref]$parsed)) {
            $parsed.ToString('D').ToLowerInvariant()
        }
    }
}
