# Purpose: Invoke-HVCreds - command entry point.
# Maintains the existing validation, logging, and execution behavior.

# Credentials command: initializes the session credentials used by Hyper-V workflows.
# Step 9.2.1 - session-only AD credential initialization.
# Adapted from SetAdminCredentials_v2.1; no dependency on shared functions.
function Invoke-HVCreds {
    [CmdletBinding()]
    param(
        [string]$DefaultDomain
    )

    if (-not $PSBoundParameters.ContainsKey('DefaultDomain')) {
        $DefaultDomain = (Get-HVModuleConfiguration).DefaultDomain
    }
    $selectedDomain = Read-Host "Domain (default $DefaultDomain)"
    if ([string]::IsNullOrWhiteSpace($selectedDomain)) { $selectedDomain = $DefaultDomain }
    $selectedDomain = $selectedDomain.Trim()

    do {
        $selectedUser = Read-Host 'Domain Username'
        if (-not [string]::IsNullOrWhiteSpace($selectedUser)) {
            $selectedUser = $selectedUser.Trim()
            break
        }
        Write-Warning 'Domain Username cannot be empty.'
    } while ($true)

    do {
        $securePassword = Read-Host 'Domain Password' -AsSecureString
        $bstr = [IntPtr]::Zero
        try {
            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
            $isEmpty = ([Runtime.InteropServices.Marshal]::ReadInt16($bstr) -eq 0)
        }
        finally {
            if ($bstr -ne [IntPtr]::Zero) {
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            }
        }
        if (-not $isEmpty) { break }
        Write-Warning 'Domain Password cannot be empty.'
    } while ($true)

    $validationResult = $null
    $context = $null
    $plainPassword = $null
    try {
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement -ErrorAction Stop
        $userForValidation = $selectedUser
        if ($userForValidation -match '^[^\\]+\\(.+)$') {
            $userForValidation = $Matches[1]
        }
        $plainPassword = (New-Object System.Net.NetworkCredential('', $securePassword)).Password
        $context = New-Object System.DirectoryServices.AccountManagement.PrincipalContext(
            [System.DirectoryServices.AccountManagement.ContextType]::Domain,
            $selectedDomain
        )
        if ($context.ValidateCredentials($userForValidation, $plainPassword)) {
            $validationResult = @{ Success = $true; Message = 'Domain credentials validated successfully.' }
        }
        else {
            $validationResult = @{ Success = $false; Message = 'Invalid domain username or password.' }
        }
    }
    catch {
        $message = $_.Exception.Message
        $friendlyMessage = switch -Regex ($message) {
            'The network path was not found' { "Domain '$selectedDomain' could not be contacted."; break }
            'The specified domain either does not exist or could not be contacted' { "Domain '$selectedDomain' does not exist or could not be contacted."; break }
            'server could not be contacted' { "Domain '$selectedDomain' could not be contacted."; break }
            default { "AD validation failed: $message" }
        }
        $validationResult = @{ Success = $false; Message = $friendlyMessage }
    }
    finally {
        $plainPassword = $null
        if ($null -ne $context) { $context.Dispose() }
    }

    if (-not $validationResult.Success) {
        Write-Host "Validation FAILED - $($validationResult.Message)" -ForegroundColor Yellow
        Write-Host 'Existing session credentials were preserved (if any).' -ForegroundColor Yellow
        return
    }

    $userForCred = $selectedUser
    if ($userForCred -notmatch '\\' -and $userForCred -notmatch '@') {
        $userForCred = "$selectedDomain\$userForCred"
    }
    $newCred = New-Object System.Management.Automation.PSCredential($userForCred, $securePassword)
    # Publish only after validation succeeds, retaining compatibility with Config v2.5.
    Set-Variable -Name Domain -Value $selectedDomain -Scope Global
    Set-Variable -Name DomainUser -Value $selectedUser -Scope Global
    Set-Variable -Name domainUserForCred -Value $userForCred -Scope Global
    Set-Variable -Name domainCred -Value $newCred -Scope Global
    Write-Host $validationResult.Message -ForegroundColor Green
}
