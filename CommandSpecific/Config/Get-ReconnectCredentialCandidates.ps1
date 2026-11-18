# Purpose: Get-ReconnectCredentialCandidates - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Retrieves reconnect Credential Candidates for the calling workflow.
function Get-ReconnectCredentialCandidates {
    param(
        [Parameter(Mandatory = $true)]
        [string]$GuestUser,

        [Parameter(Mandatory = $true)]
        [string]$GuestPass,

        [Parameter(Mandatory = $true)]
        [string]$ComputerName
    )

    $secure = ConvertTo-SecureString $GuestPass -AsPlainText -Force
    $candidates = New-Object System.Collections.ArrayList

    # Adds cred Candidate for the calling workflow.
    function Add-CredCandidate {
        param(
            [System.Collections.ArrayList]$List,
            [string]$UserName,
            [securestring]$Password
        )

        if ([string]::IsNullOrWhiteSpace($UserName)) {
            return
        }

        $already = $List | Where-Object { $_.UserName -eq $UserName } | Select-Object -First 1
        if (-not $already) {
            [void]$List.Add((New-Object System.Management.Automation.PSCredential($UserName, $Password)))
        }
    }

    Add-CredCandidate -List $candidates -UserName $GuestUser -Password $secure

    if ($GuestUser -like '.\*') {
        $shortUser = $GuestUser.Substring(2)
        Add-CredCandidate -List $candidates -UserName ".\$shortUser" -Password $secure
        Add-CredCandidate -List $candidates -UserName "$ComputerName\$shortUser" -Password $secure
        Add-CredCandidate -List $candidates -UserName $shortUser -Password $secure
    }
    elseif ($GuestUser -notmatch '\\' -and $GuestUser -notmatch '@') {
        Add-CredCandidate -List $candidates -UserName ".\$GuestUser" -Password $secure
        Add-CredCandidate -List $candidates -UserName "$ComputerName\$GuestUser" -Password $secure
        Add-CredCandidate -List $candidates -UserName $GuestUser -Password $secure
    }
    else {
        $leafUser = $GuestUser.Split('\')[-1]
        Add-CredCandidate -List $candidates -UserName ".\$leafUser" -Password $secure
        Add-CredCandidate -List $candidates -UserName "$ComputerName\$leafUser" -Password $secure
    }

    return @($candidates)
}
