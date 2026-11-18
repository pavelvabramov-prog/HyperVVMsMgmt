# Purpose: Invoke-PsDirectWithRetry - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Runs ps Direct With Retry for the calling workflow.
function Invoke-PsDirectWithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMName,

        [Parameter(Mandatory = $true)]
        [pscredential]$Credential,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [AllowEmptyCollection()]
        [object[]]$ArgumentList = @(),

        [int]$Attempts = 8,
        [int]$DelaySeconds = 10,
        [string]$StepName = "PowerShell Direct operation"
    )

    $lastError = $null

    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            if ($null -ne $ArgumentList -and $ArgumentList.Count -gt 0) {
                return Invoke-Command `
                    -VMName $VMName `
                    -Credential $Credential `
                    -ScriptBlock $ScriptBlock `
                    -ArgumentList $ArgumentList `
                    -ErrorAction Stop
            }
            else {
                return Invoke-Command `
                    -VMName $VMName `
                    -Credential $Credential `
                    -ScriptBlock $ScriptBlock `
                    -ErrorAction Stop
            }
        }
    catch {
        $lastError = ($_ | Out-String).Trim()

        if ($i -ge 5) {
            Write-Warning "$StepName failed on attempt $i/$Attempts. Retrying in $DelaySeconds seconds..."
        }

        Start-Sleep -Seconds $DelaySeconds
    }
    }

    throw "$StepName failed after $Attempts attempts. Last error: $lastError"
}
