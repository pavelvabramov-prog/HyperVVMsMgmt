# Shared selection policy for all three workflows. Discovery/classification stays with callers.
# Returns structured status and selected candidates; no VM changes occur here.
function Resolve-HVBatchSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RequestedName,
        [Parameter(Mandatory)][object[]]$Candidates,
        [ValidateSet('Single','Multiple')][string]$PermittedSelection = 'Single',
        [Parameter(Mandatory)]$SelectionContext,
        [switch]$ValidateOnly,
        [switch]$ConfirmSelection,
        [switch]$CancelEntireBatch,
        [switch]$SuppressCandidateDisplay,
        [string[]]$InputNames = @()
    )
    $hits = @(Sort-HVSelectionCandidates -Candidates $Candidates -InputNames $InputNames -RequestedName $RequestedName)
    if ($hits.Count -eq 0) { return [pscustomobject]@{Status='NotFound';Selected=@();Reason='No matching VM'} }
    # Any overlap blocks the WHOLE later input entry, even when other hits are new.
    $excluded = @($hits | Where-Object { $SelectionContext.Excluded.ContainsKey([string]$_.Id) })
    if ($excluded.Count -gt 0) {
        Write-Warning ("Skipping entry for '{0}' (VM '{1}' already EXCLUDED by earlier selection)." -f $RequestedName, $excluded[0].Name)
        return [pscustomobject]@{Status='Skipped';Selected=@();Reason='ExcludedByEarlierSelection'}
    }
    $already = @($hits | Where-Object { $SelectionContext.Selected.ContainsKey([string]$_.Id) })
    if ($already.Count -gt 0) {
        Write-Warning ("Skipping entry for '{0}' (VM '{1}' already INCLUDED by earlier selection)." -f $RequestedName, $already[0].Name)
        return [pscustomobject]@{Status='Skipped';Selected=@();Reason='AlreadySelectedByEarlierEntry'}
    }
    $chosen = @()
    if ($hits.Count -eq 1) { $chosen = @($hits[0]) }
    else {
        if (-not $SuppressCandidateDisplay) {
            Write-Host "Candidate Hyper-V VM objects for '$RequestedName':" -ForegroundColor Yellow
            for ($i=0; $i -lt $hits.Count; $i++) {
                $h=$hits[$i]
                Write-Host (' [{0}] {1} | Host={2} | Match={3} | State={4} | Id={5}' -f ($i+1),$h.Name,$h.Node,$h.Kind,$h.State,$h.Id)
            }
        }
        while ($true) {
            $prompt = if ($PermittedSelection -eq 'Multiple') {"Select VM(s) [1-$($hits.Count)] (comma-separated), or Q to cancel"} else {"Select VM [1-$($hits.Count)], or Q to cancel"}
            $answer = (Read-Host $prompt).Trim()
            if ($answer -match '^[Qq]$') {
                if ($CancelEntireBatch) { throw 'VM selection cancelled. No changes started.' }
                return [pscustomobject]@{Status='Skipped';Selected=@();Reason='SelectionCancelled'}
            }
            $parts = @($answer -split ',' | ForEach-Object { $_.Trim() })
            $numbers = @();$valid=($parts.Count -gt 0)
            if ($PermittedSelection -eq 'Single' -and $parts.Count -ne 1) {$valid=$false}
            foreach ($part in $parts) {
                $number=0
                if (-not [int]::TryParse($part,[ref]$number) -or $number -lt 1 -or $number -gt $hits.Count -or $numbers -contains $number) {$valid=$false;break}
                $numbers += $number
            }
            if ($valid) { $chosen=@($numbers | ForEach-Object { $hits[$_-1] });break }
            Write-Warning 'Invalid selection; enter unique candidate numbers in range.'
        }
        if ($ConfirmSelection -and -not $ValidateOnly) {
            foreach ($h in $chosen) {
                Write-Warning ("Confirm selected VM: '{0}' on '{1}' (ID {2})." -f $h.Name,$h.Node,$h.Id)
                $yes = Read-Host 'Enter Y to confirm, anything else cancels'
                if ($yes -notin @('Y','y')) {
                    if ($CancelEntireBatch) { throw 'VM selection not confirmed. No changes started.' }
                    return [pscustomobject]@{Status='Skipped';Selected=@();Reason='ConfirmationDeclined'}
                }
            }
        }
    }
    # Display the actual candidate VM names, not the requested short name.
    # Only ambiguous groups need a selection summary. This is display-only.
    if ($hits.Count -gt 1) {
        $chosenIdsForDisplay = @($chosen | ForEach-Object { [string]$_.Id })
        Write-Host ''
        Write-Host 'Selection results:' -ForegroundColor Cyan
        for ($i = 0; $i -lt $hits.Count; $i++) {
            $candidate = $hits[$i]
            $status = if ([string]$candidate.Id -in $chosenIdsForDisplay) { 'SELECTED' } else { 'EXCLUDED' }
            Write-Host (' [{0}] {1} | {2}' -f ($i + 1), $candidate.Name, $status)
        }
        Write-Host ''
    }
    foreach ($h in $chosen) { $SelectionContext.Selected[[string]$h.Id] = $true }
    if ($hits.Count -gt 1) {
        $chosenIds = @($chosen | ForEach-Object { [string]$_.Id })
        foreach ($h in $hits) {
            if ([string]$h.Id -notin $chosenIds) { $SelectionContext.Excluded[[string]$h.Id] = $true }
        }
    }
    [pscustomobject]@{Status='Selected';Selected=@($chosen);Reason=''}
}
