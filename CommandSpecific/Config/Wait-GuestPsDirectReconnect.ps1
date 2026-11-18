# Purpose: Wait-GuestPsDirectReconnect - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Waits for guest Ps Direct Reconnect for the calling workflow.
function Wait-GuestPsDirectReconnect {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMName,

        [Parameter(Mandatory = $true)]
        [pscredential[]]$CredentialCandidates,

        [int]$InitialDelaySec = 20,
        [int]$AttemptsPerCredential = 8,
        [int]$DelayBetweenAttemptsSec = 10
    )

    Write-Host "INFO: Waiting extra time for guest logon services after restart..." -ForegroundColor Cyan
    Start-Sleep -Seconds $InitialDelaySec

    $lastError = $null

    foreach ($candidate in $CredentialCandidates) {
        Write-Host "INFO: Trying PowerShell Direct reconnect with user '$($candidate.UserName)'" -ForegroundColor Cyan

        for ($i = 1; $i -le $AttemptsPerCredential; $i++) {
            try {
                Invoke-Command -VMName $VMName -Credential $candidate -ScriptBlock { "ok" } -ErrorAction Stop | Out-Null
                Write-Host "INFO: Reconnect with PowerShell Direct succeeded using '$($candidate.UserName)'" -ForegroundColor Green
                return $candidate
            }
            catch {
                $lastError = ($_ | Out-String).Trim()
                Start-Sleep -Seconds $DelayBetweenAttemptsSec
            }
        }
    }

    throw "AUTHFAIL: Could not reconnect to VM '$VMName' with PowerShell Direct after restart. Last error: $lastError"
}
