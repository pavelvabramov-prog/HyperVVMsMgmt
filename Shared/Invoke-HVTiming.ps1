# Purpose: Invoke-HVTiming - shared helper.
# Maintains the existing validation, logging, and execution behavior.

# Measures and reports optional execution timing without changing the workflow.
function Invoke-HVTiming {
    [CmdletBinding(DefaultParameterSetName='Action')]
    param(
        [Parameter(Mandatory=$true)][ValidateSet('Reset','Start','Stop','Measure','Report')][string]$Action,
        [Parameter(Mandatory=$false)][string]$TimingLabel,
        [string]$Target = '',
        [scriptblock]$ScriptBlock,
        [ValidateSet('OK','FAILED')][string]$Result = 'OK',
        [switch]$Enabled
    )
    # The context is reset at the beginning and cleared at the end of each command invocation.
    # Use a dedicated module-scoped context rather than the old global timing rows.
    if ($Action -eq 'Reset') {
        $script:HVTimingContext = @{
            Enabled = [bool]$Enabled
            Overall = [System.Diagnostics.Stopwatch]::StartNew()
            Rows = New-Object 'System.Collections.Generic.List[object]'
            Active = @{}
        }
        return
    }
    $ctx = $script:HVTimingContext
    if ($null -eq $ctx) {
        if ($Action -eq 'Measure') {
            if ($null -eq $ScriptBlock) { throw 'Measure requires -ScriptBlock.' }
            & $ScriptBlock
        }
        return
    }
    switch ($Action) {
        'Measure' {
            if ($null -eq $ScriptBlock) { throw 'Measure requires -ScriptBlock.' }
            if (-not $ctx.Enabled) { & $ScriptBlock; return }
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $outcome = 'OK'
            try { & $ScriptBlock }
            catch { $outcome = 'FAILED'; throw }
            finally {
                $sw.Stop()
                $row = [pscustomobject]@{Operation=$TimingLabel;Target=$Target;DurationMs=[math]::Round($sw.Elapsed.TotalMilliseconds,1);Result=$outcome}
                $ctx.Rows.Add($row) | Out-Null
                Write-Host ('[TIMING] {0} | {1} | {2:N1} ms | {3}' -f $TimingLabel,$Target,$row.DurationMs,$outcome)
            }
        }
        'Start' {
            if (-not $ctx.Enabled) { return }
            if (-not $TimingLabel) { throw 'Start requires -Name.' }
            $key = "$TimingLabel`n$Target"
            if ($ctx.Active.ContainsKey($key)) { throw "Timing operation already started: $TimingLabel ($Target)" }
            $ctx.Active[$key] = [System.Diagnostics.Stopwatch]::StartNew()
        }
        'Stop' {
            if (-not $ctx.Enabled) { return }
            $key = "$TimingLabel`n$Target"
            if (-not $ctx.Active.ContainsKey($key)) { throw "Timing operation was not started: $TimingLabel ($Target)" }
            $sw = $ctx.Active[$key]
            $sw.Stop()
            [void]$ctx.Active.Remove($key)
            $row = [pscustomobject]@{Operation=$TimingLabel;Target=$Target;DurationMs=[math]::Round($sw.Elapsed.TotalMilliseconds,1);Result=$Result}
            $ctx.Rows.Add($row) | Out-Null
            Write-Host ('[TIMING] {0} | {1} | {2:N1} ms | {3}' -f $TimingLabel,$Target,$row.DurationMs,$Result)
        }
        'Report' {
            try {
                $ctx.Overall.Stop()
                if ($ctx.Enabled) {
                    Write-Host "`n========== PERFORMANCE TIMING ==========" -ForegroundColor Cyan
                    # Summarize repetitive cluster parameter queries per target while
                    # retaining every individual [TIMING] event during execution.
                    $lookupGroups = @($ctx.Rows | Where-Object { $_.Operation -eq 'Cluster resource parameter lookup' } | Group-Object -Property Target)
                    $printedLookups = @{}
                    foreach ($r in $ctx.Rows) {
                        if ($r.Operation -eq 'Cluster resource parameter lookup') {
                            if ($printedLookups.ContainsKey([string]$r.Target)) { continue }
                            $printedLookups[[string]$r.Target] = $true
                            $group = @($lookupGroups | Where-Object { $_.Name -eq [string]$r.Target })[0]
                            $totalMs = ($group.Group | Measure-Object -Property DurationMs -Sum).Sum
                            $status = if (@($group.Group | Where-Object { $_.Result -ne 'OK' }).Count -gt 0) { 'FAILED' } else { 'OK' }
                            Write-Host ('{0,-38} {1,-22} {2,12:N1} ms  {3}' -f ('Cluster parameter lookups ({0} calls)' -f $group.Count),$r.Target,$totalMs,$status)
                            continue
                        }
                        Write-Host ('{0,-38} {1,-22} {2,12:N1} ms  {3}' -f $r.Operation,$r.Target,$r.DurationMs,$r.Result)
                    }
                    Write-Host ('Total elapsed (including prompts): {0:N2} s' -f $ctx.Overall.Elapsed.TotalSeconds)
                    Write-Host 'Note: nested measurements overlap; do not sum rows.'
                    Write-Host '========================================' -ForegroundColor Cyan
                }
            } finally {
                $script:HVTimingContext = $null
            }
        }
    }
}
