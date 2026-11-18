# Purpose: Remove-JumpHostADComputer - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Removes jump Host ADComputer for the calling workflow.
function Remove-JumpHostADComputer {
    param([string]$ComputerName,[object]$Status,[bool]$ResetAccount)
    if ($Status.Status -ne 'Found') {
        if ($Status.Status -eq 'NotFound') {
            Write-Host "AD computer '$ComputerName' not found. No deletion required."
        } else {
            Write-Warning "AD cleanup NOT performed for '$ComputerName': $($Status.Status) $($Status.Error)"
        }
        return
    }
    try {
        if ($ResetAccount) {
            Set-ADAccountPassword -Identity $Status.DN -Reset -NewPassword (ConvertTo-SecureString ([guid]::NewGuid().ToString('N') + 'aA1!') -AsPlainText -Force) -ErrorAction Stop
            Write-Host "AD computer password reset (account preserved): $($Status.DN)" -ForegroundColor Green
        } else {
            Remove-ADComputer -Identity $Status.DN -Confirm:$false -ErrorAction Stop
            Write-Host "AD computer removed from JumpHost: $($Status.DN)" -ForegroundColor Green
        }
    }
    catch {
        if (-not $ResetAccount -and $_.Exception.Message -match 'leaf object') {
            try {
                Remove-ADObject -Identity $Status.DN -Recursive -Confirm:$false -ErrorAction Stop
                Write-Host "AD computer removed recursively from JumpHost: $($Status.DN)" -ForegroundColor Green
                return
            } catch { Write-Warning "AD recursive removal failed: $($_.Exception.Message)"; return }
        }
        Write-Warning "AD removal failed for '$ComputerName': $($_.Exception.Message)"
    }
}
