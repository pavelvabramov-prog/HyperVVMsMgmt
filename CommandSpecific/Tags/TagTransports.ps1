# Purpose: Get-DesiredTags - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Tag storage locations are read from Config/HyperVTools.config.txt at runtime.
# Retrieves desired Tags for the calling workflow.
function Get-DesiredTags {
    param (
        [string[]]$ExistingTags,
        [string[]]$RequestedTags,

        [Parameter(Mandatory)]
        [string]$Action
    )

    switch ($Action) {
        'Get' {
            return @($ExistingTags)
        }

        'Add' {
            return @(
                $ExistingTags + $RequestedTags |
                    Sort-Object -Unique
            )
        }

        'Remove' {
            return @(
                $ExistingTags |
                    Where-Object { $_ -notin $RequestedTags } |
                    Sort-Object -Unique
            )
        }

        'Set' {
            # Replace all values in requested categories; keep other categories intact.
            $requestedCategories = @{}
            foreach ($tag in @($RequestedTags)) {
                if ($tag -match '^([^:]+):') { $requestedCategories[$Matches[1]] = $true }
            }
            $preserved = @($ExistingTags | Where-Object {
                if ($_ -match '^([^:]+):') { -not $requestedCategories.ContainsKey($Matches[1]) }
                else { $true }
            })
            return @(ConvertTo-HVOrderedTags -Tags @($preserved + $RequestedTags))
        }

        'ReplaceAll' {
            return @(ConvertTo-HVOrderedTags -Tags $RequestedTags)
        }

        'Clear' {
            return @()
        }
    }
}

# ============================================================================
# HYPER-V NOTES FUNCTIONS
# ============================================================================

# ============================================================================
# HYPER-V VM LOOKUP
# ============================================================================

# Existing VM matching is delegated to Shared/Resolve-HVExistingVM.ps1.
# That resolver uses hv-config's shared classification and selection interface.

# ============================================================================
# HYPER-V TAG OPERATION
# ============================================================================

# Runs hyper VTag Operation for the calling workflow.
function Invoke-HyperVTagOperation {
    param (
        [Parameter(Mandatory)]
        [string]$VMName,

        [Parameter(Mandatory)]
        [string]$HyperVHost,

        [Parameter(Mandatory)]
        [string]$Action,

        [string[]]$RequestedTags,

        [switch]$ValidateOnly,
        $PreResolved
    )

    $Resolved = if ($null -ne $PreResolved) { $PreResolved } else { Resolve-HVExistingVM `
        -VMName $VMName `
        -HyperVHost $HyperVHost `
        -ValidateOnly:$ValidateOnly `
        -ReadOnly:($Action -eq 'Get') }

    if ($Resolved.Status -eq 'Skipped') {
        return [pscustomobject]@{
            ComputerName = $VMName
            Type = 'HyperV'
            Cluster = $HyperVHost
            Action = $Action
            Changed = $false
            ValidateOnly = [bool]$ValidateOnly
            Status = 'Skipped'
            Reason = $Resolved.Reason
        }
    }

    $VM = $Resolved.VM

    $ExistingTags = @(
        Get-TagsFromNotes -Notes $VM.Notes
    )

    $FinalTags = @(
        Get-DesiredTags `
            -ExistingTags $ExistingTags `
            -RequestedTags $RequestedTags `
            -Action $Action
    )

    $OldTagString = Format-HVReadableTags -Tags $ExistingTags
    $NewTagString = Format-HVReadableTags -Tags $FinalTags
    $Changed      = -not (Test-HVTagSetEqual -Left $ExistingTags -Right $FinalTags)

    if (
        $Action -ne 'Get' -and
        $Changed -and
        -not $ValidateOnly
    ) {
        $NewNotes = Set-TagsInNotes `
            -Notes $VM.Notes `
            -NewTags $FinalTags

        Set-HVTagsForVMId -VMId ([string]$Resolved.VMId) -ExpectedName ([string]$Resolved.VMName) -HyperVHost ([string]$Resolved.HyperVHost) -NewNotes $NewNotes

    }

    if ($Action -eq 'Get') {
        [PSCustomObject]@{
            ComputerName = $VMName
            VMName       = $Resolved.VMName
            Type         = 'HyperV'
            Cluster      = $Resolved.Cluster
            HyperVHost   = $Resolved.HyperVHost
            Action       = $Action
            Tags         = $NewTagString
            Status       = 'Success'
        }

        return
    }

    [PSCustomObject]@{
        ComputerName = $VMName
        VMName       = $Resolved.VMName
        Type         = 'HyperV'
        Cluster      = $Resolved.Cluster
        HyperVHost   = $Resolved.HyperVHost
        Action       = $Action
        PreviousTags = $OldTagString
        Tags         = $NewTagString
        Changed      = $Changed
        ValidateOnly = [bool]$ValidateOnly
        Status       = 'Success'
    }

    if (-not $Changed) {
        Write-Host ""
        Write-Host "No tag changes are required."
        Write-Host ""
    }
    elseif ($ValidateOnly) {
        Write-Host ""
        Write-Host "VALIDATE ONLY - No changes were made."
        Write-Host ""
    }
    else {
        Write-Host ""
        Write-Host "Tags updated successfully."
        Write-Host ""
    }
}

# ============================================================================
# PHYSICAL WINDOWS - CONNECTION
# ============================================================================

# Retrieves trusted Hosts Value for the calling workflow.
function Get-TrustedHostsValue {
    try {
        return [string](
            Get-Item `
                WSMan:\localhost\Client\TrustedHosts `
                -ErrorAction Stop
        ).Value
    }
    catch {
        throw (
            "Unable to read the local WinRM TrustedHosts configuration. " +
            $_.Exception.Message
        )
    }
}

# Checks trusted Host Covered for the calling workflow.
function Test-TrustedHostCovered {
    param (
        [string]$TrustedHostsValue,

        [Parameter(Mandatory)]
        [string]$ConnectionTarget
    )

    if ([string]::IsNullOrWhiteSpace($TrustedHostsValue)) {
        return $false
    }

    $Entries = @(
        $TrustedHostsValue -split ',' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
    )

    foreach ($Entry in $Entries) {
        if ($ConnectionTarget -like $Entry) {
            return $true
        }
    }

    return $false
}

# Handles trusted Hosts for the calling workflow.
function Restore-TrustedHosts {
    param (
        [AllowEmptyString()]
        [string]$OriginalValue
    )

    Write-Verbose "Restoring the original WinRM TrustedHosts configuration..."

    if ([string]::IsNullOrWhiteSpace($OriginalValue)) {
        Clear-Item `
            WSMan:\localhost\Client\TrustedHosts `
            -Force `
            -ErrorAction Stop
    }
    else {
        Set-Item `
            WSMan:\localhost\Client\TrustedHosts `
            -Value $OriginalValue `
            -Force `
            -ErrorAction Stop
    }

    Write-Verbose "Original WinRM TrustedHosts configuration restored."
}

# Handles physical Windows Server for the calling workflow.
function Connect-PhysicalWindowsServer {
    param (
        [Parameter(Mandatory)]
        [string]$ComputerName
    )

    $ResolvedByDNS      = $false
    $ResolvedDnsName    = $null
    $ResolvedIP         = $null
    $ConnectionTarget   = $null
    $TrustedHostsChanged = $false
    $OriginalTrustedHosts = $null

    # ------------------------------------------------------------------------
    # 1. Resolve the supplied name.
    # ------------------------------------------------------------------------

    Write-Verbose "Resolving '$ComputerName'..."

    try {
        $DnsResult = [System.Net.Dns]::GetHostEntry($ComputerName)

        if ($DnsResult) {
            $ResolvedByDNS   = $true
            $ResolvedDnsName = $DnsResult.HostName

            $IPv4Addresses = @(
                $DnsResult.AddressList |
                    Where-Object {
                        $_.AddressFamily -eq
                        [System.Net.Sockets.AddressFamily]::InterNetwork
                    } |
                    ForEach-Object {
                        $_.IPAddressToString
                    }
            )

            if ($IPv4Addresses.Count -gt 0) {
                $ResolvedIP = $IPv4Addresses[0]
            }

            if (-not [string]::IsNullOrWhiteSpace($ResolvedDnsName)) {
                $ConnectionTarget = $ResolvedDnsName
            }
            else {
                $ConnectionTarget = $ComputerName
            }

            Write-Verbose "Resolved DNS name: $ResolvedDnsName"

            if ($ResolvedIP) {
                Write-Verbose "Resolved IPv4 address: $ResolvedIP"
            }

            Write-Verbose "Connection target: $ConnectionTarget"
        }
    }
    catch {
        Write-Verbose (
            "DNS resolution failed for '$ComputerName': " +
            $_.Exception.Message
        )
    }

    # ------------------------------------------------------------------------
    # 2. DNS failed - request an IPv4 address.
    # ------------------------------------------------------------------------

    if (-not $ResolvedByDNS) {
        Write-Host ""
        Write-Warning "Unable to resolve '$ComputerName' in DNS."
        Write-Host ""
        Write-Host "Enter the IPv4 address for '$ComputerName'."
        Write-Host "Press Enter without entering an address to cancel."
        Write-Host ""

        $ManualIP = Read-Host "IP address"

        if ([string]::IsNullOrWhiteSpace($ManualIP)) {
            throw @"
Unable to resolve '$ComputerName' in DNS and no IP address was supplied.

No connection was attempted.
"@
        }

        $ParsedIP = $null

        if (
            -not [System.Net.IPAddress]::TryParse(
                $ManualIP.Trim(),
                [ref]$ParsedIP
            )
        ) {
            throw "'$ManualIP' is not a valid IP address."
        }

        if (
            $ParsedIP.AddressFamily -ne
            [System.Net.Sockets.AddressFamily]::InterNetwork
        ) {
            throw "'$ManualIP' is not a valid IPv4 address."
        }

        $ResolvedIP       = $ParsedIP.IPAddressToString
        $ConnectionTarget = $ResolvedIP

        Write-Verbose (
            "Using manually supplied IP address '$ConnectionTarget' " +
            "for '$ComputerName'."
        )
    }

    # ------------------------------------------------------------------------
    # 3. Test WinRM before asking for credentials.
    # ------------------------------------------------------------------------

    Write-Verbose "Testing WinRM on '$ConnectionTarget'..."

    try {
        Test-WSMan `
            -ComputerName $ConnectionTarget `
            -ErrorAction Stop |
            Out-Null

        Write-Verbose "WinRM is available."
    }
    catch {
        $WinRMError = $_.Exception.Message

        throw @"
Unable to establish WinRM connectivity to '$ComputerName'.

Connection target : $ConnectionTarget
DNS resolved      : $ResolvedByDNS
Resolved DNS name : $ResolvedDnsName
IP address        : $ResolvedIP

WinRM is not responding successfully.

Possible causes include:
  - The server is offline or unreachable
  - WinRM is not enabled
  - The WinRM service is stopped
  - The firewall is blocking WinRM
  - Network routing does not permit the connection

WinRM error:
$WinRMError

No credentials were requested because WinRM connectivity was not established.
"@
    }

    # ------------------------------------------------------------------------
    # 4. Try current Windows session credentials.
    # ------------------------------------------------------------------------

    Write-Verbose (
        "Testing current Windows session credentials on " +
        "'$ConnectionTarget'..."
    )

    try {
        $Session = New-PSSession `
            -ComputerName $ConnectionTarget `
            -ErrorAction Stop

        Write-Verbose (
            "Connected to '$ComputerName' using current session credentials."
        )

        return [PSCustomObject]@{
            Session              = $Session
            AuthenticationType   = 'CurrentSession'
            UserName             = $env:USERDOMAIN + '\' + $env:USERNAME
            ConnectionTarget     = $ConnectionTarget
            ResolvedByDNS        = $ResolvedByDNS
            ResolvedDnsName      = $ResolvedDnsName
            IPAddress            = $ResolvedIP
            TrustedHostsChanged  = $false
            OriginalTrustedHosts = $null
        }
    }
    catch {
        $CurrentCredentialError = $_.Exception.Message

        Write-Verbose (
            "Current session authentication failed: " +
            $CurrentCredentialError
        )
    }

    # ------------------------------------------------------------------------
    # 5. Ask for alternate credentials.
    # ------------------------------------------------------------------------

    Write-Host ""
    Write-Host (
        "WinRM is available on '$ConnectionTarget', but the current " +
        "Windows session could not establish an authenticated session."
    )
    Write-Host ""
    Write-Host (
        "Please enter credentials with administrative access to " +
        "'$ComputerName'."
    )
    Write-Host ""

    $Credential = Get-Credential `
        -Message "Enter administrative credentials for $ComputerName"

    if (-not $Credential) {
        throw @"
Credential entry was cancelled.

Computer name     : $ComputerName
Connection target : $ConnectionTarget

No connection was established.
"@
    }

    Write-Verbose (
        "Testing alternate credentials '$($Credential.UserName)' " +
        "against '$ConnectionTarget'..."
    )

    # ------------------------------------------------------------------------
    # 6. Test alternate credentials normally.
    # ------------------------------------------------------------------------

    try {
        $Session = New-PSSession `
            -ComputerName $ConnectionTarget `
            -Credential $Credential `
            -Authentication Negotiate `
            -ErrorAction Stop

        Write-Verbose (
            "Connected to '$ComputerName' using alternate credentials " +
            "'$($Credential.UserName)'."
        )

        return [PSCustomObject]@{
            Session              = $Session
            AuthenticationType   = 'AlternateCredential'
            UserName             = $Credential.UserName
            ConnectionTarget     = $ConnectionTarget
            ResolvedByDNS        = $ResolvedByDNS
            ResolvedDnsName      = $ResolvedDnsName
            IPAddress            = $ResolvedIP
            TrustedHostsChanged  = $false
            OriginalTrustedHosts = $null
        }
    }
    catch {
        $AlternateCredentialError = $_.Exception.Message

        Write-Verbose (
            "Alternate credential authentication failed: " +
            $AlternateCredentialError
        )
    }

    # ------------------------------------------------------------------------
    # 7. TrustedHosts fallback.
    #
    #    Preserve the complete original value. If the target is not already
    #    covered by the existing configuration, temporarily add it and retry.
    #    The caller restores the original value after a successful connection.
    #    If the retry itself fails, this function restores it before throwing.
    # ------------------------------------------------------------------------

    try {
        $OriginalTrustedHosts = Get-TrustedHostsValue

        if (
            Test-TrustedHostCovered `
                -TrustedHostsValue $OriginalTrustedHosts `
                -ConnectionTarget $ConnectionTarget
        ) {
            Write-Verbose (
                "'$ConnectionTarget' is already covered by the local " +
                "WinRM TrustedHosts configuration."
            )
        }
        else {
            Write-Verbose (
                "Temporarily adding '$ConnectionTarget' to the local " +
                "WinRM TrustedHosts list."
            )

            Set-Item `
                WSMan:\localhost\Client\TrustedHosts `
                -Value $ConnectionTarget `
                -Concatenate `
                -Force `
                -ErrorAction Stop

            $TrustedHostsChanged = $true
        }

        Write-Verbose (
            "Retrying alternate credentials '$($Credential.UserName)' " +
            "against '$ConnectionTarget'..."
        )

        $Session = New-PSSession `
            -ComputerName $ConnectionTarget `
            -Credential $Credential `
            -Authentication Negotiate `
            -ErrorAction Stop

        Write-Verbose (
            "Connected to '$ComputerName' using alternate credentials."
        )

        if ($TrustedHostsChanged) {
            Write-Verbose (
                "The TrustedHosts change is temporary and will be restored " +
                "when the tag operation finishes."
            )
        }

        return [PSCustomObject]@{
            Session              = $Session
            AuthenticationType   = if ($TrustedHostsChanged) {
                                       'AlternateCredential+TrustedHosts'
                                   }
                                   else {
                                       'AlternateCredential'
                                   }
            UserName             = $Credential.UserName
            ConnectionTarget     = $ConnectionTarget
            ResolvedByDNS        = $ResolvedByDNS
            ResolvedDnsName      = $ResolvedDnsName
            IPAddress            = $ResolvedIP
            TrustedHostsChanged  = $TrustedHostsChanged
            OriginalTrustedHosts = $OriginalTrustedHosts
        }
    }
    catch {
        $TrustedHostsRetryError = $_.Exception.Message

        Write-Verbose (
            "TrustedHosts authentication retry failed: " +
            $TrustedHostsRetryError
        )

        if ($TrustedHostsChanged) {
            try {
                Restore-TrustedHosts `
                    -OriginalValue $OriginalTrustedHosts
            }
            catch {
                Write-Warning (
                    "Unable to restore the original WinRM TrustedHosts " +
                    "configuration automatically: " +
                    $_.Exception.Message
                )
            }
        }

        Write-Verbose "Authentication diagnostics:"
        Write-Verbose "  Computer name     : $ComputerName"
        Write-Verbose "  Resolved DNS name : $ResolvedDnsName"
        Write-Verbose "  IP address        : $ResolvedIP"
        Write-Verbose "  Connection target : $ConnectionTarget"
        Write-Verbose "  WinRM             : Available"
        Write-Verbose "  User              : $($Credential.UserName)"

        throw @"
Unable to authenticate to '$ComputerName' using the supplied credentials.

No changes were made.
"@
    }
}

# ============================================================================
# PHYSICAL WINDOWS - READ TAGS
# ============================================================================

# Retrieves physical Windows Tags for the calling workflow.
function Get-PhysicalWindowsTags {
    param (
        [Parameter(Mandatory)]
        [System.Management.Automation.Runspaces.PSSession]$Session
    )

    $TagString = Invoke-Command `
        -Session $Session `
        -ArgumentList (Get-HVModuleConfiguration).WindowsRegistryPath `
        -ScriptBlock {
            param([string]$RegistryPath)

            if (-not (Test-Path $RegistryPath)) {
                return ''
            }

            try {
                $Value = Get-ItemPropertyValue `
                    -Path $RegistryPath `
                    -Name 'Tags' `
                    -ErrorAction Stop
            }
            catch {
                return ''
            }

            if ($null -eq $Value) {
                return ''
            }

            return [string]$Value
        } `
        -ErrorAction Stop

    if ([string]::IsNullOrWhiteSpace($TagString)) {
        return @()
    }

    return @(
        ConvertTo-NormalizedTags `
            -InputTags ($TagString -split ';')
    )
}

# ============================================================================
# PHYSICAL WINDOWS - WRITE TAGS
# ============================================================================

# Updates physical Windows Tags for the calling workflow.
function Set-PhysicalWindowsTags {
    param (
        [Parameter(Mandatory)]
        [System.Management.Automation.Runspaces.PSSession]$Session,

        [string[]]$NewTags
    )

    $TagString = $NewTags -join ';'

    Invoke-Command `
        -Session $Session `
        -ArgumentList $TagString, (Get-HVModuleConfiguration).WindowsRegistryPath `
        -ScriptBlock {
            param ([string]$TagString, [string]$RegistryPath)

            if (-not [string]::IsNullOrWhiteSpace($TagString)) {
                if (-not (Test-Path $RegistryPath)) {
                    New-Item `
                        -Path $RegistryPath `
                        -Force `
                        -ErrorAction Stop |
                        Out-Null
                }

                New-ItemProperty `
                    -Path $RegistryPath `
                    -Name 'Tags' `
                    -Value $TagString `
                    -PropertyType String `
                    -Force `
                    -ErrorAction Stop |
                    Out-Null

                return
            }

            # Clear only Tags. Preserve ServerMetadata for future values.
            if (Test-Path $RegistryPath) {
                Remove-ItemProperty `
                    -Path $RegistryPath `
                    -Name 'Tags' `
                    -ErrorAction SilentlyContinue
            }
        } `
        -ErrorAction Stop
}

# ============================================================================
# PHYSICAL WINDOWS TAG OPERATION
# ============================================================================

# Runs physical Windows Tag Operation for the calling workflow.
function Invoke-PhysicalWindowsTagOperation {
    param (
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [string]$Action,

        [string[]]$RequestedTags,

        [switch]$ValidateOnly
    )

    $Connection = $null

    try {
        $Connection = Connect-PhysicalWindowsServer `
            -ComputerName $ComputerName

        $Session = $Connection.Session

        $ExistingTags = @(
            Get-PhysicalWindowsTags -Session $Session
        )

        $FinalTags = @(
            Get-DesiredTags `
                -ExistingTags $ExistingTags `
                -RequestedTags $RequestedTags `
                -Action $Action
        )

        $OldTagString = Format-HVReadableTags -Tags $ExistingTags
        $NewTagString = Format-HVReadableTags -Tags $FinalTags
        $Changed      = -not (Test-HVTagSetEqual -Left $ExistingTags -Right $FinalTags)

        if (
            $Action -ne 'Get' -and
            $Changed -and
            -not $ValidateOnly
        ) {
            Set-PhysicalWindowsTags `
                -Session $Session `
                -NewTags $FinalTags
        }

        if ($Action -eq 'Get') {
            [PSCustomObject]@{
                ComputerName   = $ComputerName
                Type           = 'PhysicalWindows'
                AccessMethod   = 'WinRM'
                Authentication = $Connection.AuthenticationType
                Action         = $Action
                Tags           = $NewTagString
                Status         = 'Success'
            }

            return
        }

        [PSCustomObject]@{
            ComputerName   = $ComputerName
            Type           = 'PhysicalWindows'
            AccessMethod   = 'WinRM'
            Authentication = $Connection.AuthenticationType
            Action         = $Action
            PreviousTags   = $OldTagString
            Tags           = $NewTagString
            Changed        = $Changed
            ValidateOnly   = [bool]$ValidateOnly
            Status         = 'Success'
        }

        if (-not $Changed) {
            Write-Host ""
            Write-Host "No tag changes are required."
            Write-Host ""
        }
        elseif ($ValidateOnly) {
            Write-Host ""
            Write-Host "VALIDATE ONLY - No changes were made."
            Write-Host ""
        }
        else {
            Write-Host ""
            Write-Host "Tags updated successfully."
            Write-Host ""
        }
    }
    finally {
        if ($Connection -and $Connection.Session) {
            Remove-PSSession `
                -Session $Connection.Session `
                -ErrorAction SilentlyContinue
        }

        if ($Connection -and $Connection.TrustedHostsChanged) {
            try {
                Restore-TrustedHosts `
                    -OriginalValue $Connection.OriginalTrustedHosts
            }
            catch {
                Write-Warning (
                    "Unable to restore the original WinRM TrustedHosts " +
                    "configuration automatically: " +
                    $_.Exception.Message
                )
            }
        }
    }
}

# ============================================================================
# PHYSICAL LINUX FUNCTIONS
# ============================================================================

# Checks is Power Shell ISE for the calling workflow.
function Test-IsPowerShellISE {
    return ($null -ne $psISE)
}

# Handles in Power Shell Console for the calling workflow.
function Restart-InPowerShellConsole {
    Write-Host ""
    Write-Host "PhysicalLinux requires an interactive standard PowerShell console."
    Write-Host "Opening a new elevated Windows PowerShell window..."
    Write-Host ""

    if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
        throw "Unable to determine the current script path for console relaunch."
    }

    $argList = @(
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-File', ('"{0}"' -f $PSCommandPath)
        '-ComputerName', ('"{0}"' -f $ComputerName)
        '-Type', 'PhysicalLinux'
        '-UserName', ('"{0}"' -f $UserName)
        '-Action', $Action
        '-ConsoleRelaunched'
    )

    if ($Tags) {
        $argList += '-Tags'
        foreach($Tag in $Tags) {
            $argList += ('"{0}"' -f $Tag)
        }
    }

    if ($ValidateOnly) {
        $argList += '-ValidateOnly'
    }

    if ($VerbosePreference -eq 'Continue') {
        $argList += '-Verbose'
    }

    $process = Start-Process `
        -FilePath 'powershell.exe' `
        -ArgumentList $argList `
        -Verb RunAs `
        -PassThru

    if (-not $process) {
        throw "Unable to launch the standard PowerShell console."
    }

    Write-Host "Linux tagging continued in the new PowerShell window."
}


# Handles if Linux Console Relaunched for the calling workflow.
function Pause-IfLinuxConsoleRelaunched {
    if ($ConsoleRelaunched) {
        Write-Host ""
        [void](Read-Host "Press Enter to close this PowerShell window")
    }
}

# Resolves linux Target for the calling workflow.
function Resolve-LinuxTarget {
    param([Parameter(Mandatory)][string]$Name)

    Write-Verbose "Resolving '$Name'..."

    try {
        $d = [Net.Dns]::GetHostEntry($Name)
        $ip = @(
            $d.AddressList |
            Where-Object AddressFamily -eq InterNetwork |
            ForEach-Object IPAddressToString
        )[0]

        $target = if($d.HostName) { $d.HostName } else { $Name }

        Write-Verbose "Resolved DNS name: $($d.HostName)"
        if($ip) { Write-Verbose "Resolved IPv4 address: $ip" }
        Write-Verbose "Connection target: $target"

        return [pscustomobject]@{
            Dns    = $d.HostName
            IP     = $ip
            Target = $target
        }
    }
    catch {
        Write-Verbose "DNS resolution failed: $($_.Exception.Message)"
    }

    Write-Warning "Unable to resolve '$Name' in DNS."
    $manual = (Read-Host "Enter IPv4 address (blank to cancel)").Trim()

    if(!$manual) {
        throw "DNS resolution failed and no IP address was supplied. No connection was attempted."
    }

    $parsed = $null
    if(
        -not [Net.IPAddress]::TryParse($manual,[ref]$parsed) -or
        $parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork
    ) {
        throw "'$manual' is not a valid IPv4 address."
    }

    [pscustomobject]@{
        Dns    = $null
        IP     = $parsed.IPAddressToString
        Target = $parsed.IPAddressToString
    }
}

# Handles sh Literal for the calling workflow.
function Quote-ShLiteral {
    param([AllowEmptyString()][string]$Value)
    return "'" + ($Value -replace "'", "'\''") + "'"
}

# Runs linux Discovery for the calling workflow.
function Invoke-LinuxDiscovery {
    param([string]$Ssh,[string]$Target,[string]$User)
    $MetadataFile = (Get-HVModuleConfiguration).LinuxMetadataFile

    $remote = @'
printf '%s\n' '__HV_TAGS_BEGIN__'
printf 'HOSTNAME='; hostname 2>/dev/null || uname -n 2>/dev/null; printf '\n'
printf 'KERNEL='; uname -srmo 2>/dev/null || uname -a 2>/dev/null; printf '\n'
printf 'OS='
if [ -r /etc/os-release ]; then sed -n 's/^PRETTY_NAME=//p' /etc/os-release | head -n 1; else printf 'UNKNOWN'; fi
printf '\n'
file=__HV_METADATA_FILE__
if [ -e "$file" ]; then
  printf '%s\n' 'EXISTS=1'
  if [ ! -r "$file" ]; then printf '%s\n' 'ERROR=METADATA_NOT_READABLE' '__HV_TAGS_END__'; exit 42; fi
  count=$(grep -c '^TAGS=' "$file" 2>/dev/null || true)
  set -- $(cksum "$file")
  printf 'FILECKSUM=%s:%s\n' "$1" "$2"
  printf 'CONTENT_B64='
  base64 "$file" 2>/dev/null | tr -d '\r\n'
  printf '\n'
else
  printf '%s\n' 'EXISTS=0' 'FILECKSUM=ABSENT' 'CONTENT_B64='
  count=0
fi
printf 'COUNT=%s\n' "$count"
if [ "$count" -gt 1 ]; then printf '%s\n' 'ERROR=DUPLICATE_TAG_LINES' '__HV_TAGS_END__'; exit 41; fi
printf 'TAGLINE='
if [ "$count" -eq 1 ]; then grep '^TAGS=' "$file" | head -n 1; fi
printf '\n%s\n' '__HV_TAGS_END__'
'@
    $remote = $remote.Replace('__HV_METADATA_FILE__', $MetadataFile)

    Write-Verbose "SSH #1: connecting without PTY; read-only, no sudo."
    $tmp=[IO.Path]::GetTempFileName()
    try {
        & $Ssh -o ConnectTimeout=10 -o ServerAliveInterval=10 -o ServerAliveCountMax=2 "$User@$Target" $remote 1> $tmp
        $rc=$LASTEXITCODE
        $out=@(Get-Content $tmp | ForEach-Object {([string]$_).TrimEnd("`r")})
        $b=[Array]::IndexOf([object[]]$out,'__HV_TAGS_BEGIN__')
        $e=[Array]::IndexOf([object[]]$out,'__HV_TAGS_END__')
        if($b -lt 0 -or $e -le $b){throw "SSH #1 completed, but the discovery response could not be validated."}

        $d=@{}
        for($i=$b+1;$i -lt $e;$i++){
            if($out[$i] -match '^([^=]+)=(.*)$'){$d[$Matches[1]]=$Matches[2]}
        }

        if($d.ERROR -eq 'DUPLICATE_TAG_LINES'){throw "$MetadataFile contains more than one TAGS= line. Manual review is required."}
        if($d.ERROR -eq 'METADATA_NOT_READABLE'){throw "$MetadataFile exists but cannot be read by '$User'."}
        if($rc -ne 0){throw "SSH #1 failed with exit code $rc."}

        $tags=@()
        if($d.TAGLINE -match '^TAGS=(.*)$'){
            $tags=@($Matches[1] -split ';' | ForEach-Object {$_.Trim()} | Where-Object {$_} | Sort-Object -Unique)
        }

        $content=''
        if($d.EXISTS -eq '1'){
            try {
                $bytes=[Convert]::FromBase64String([string]$d.CONTENT_B64)
                $content=[Text.Encoding]::UTF8.GetString($bytes)
            } catch {
                throw "The existing metadata file could not be decoded safely. No changes were attempted."
            }
        }

        [pscustomobject]@{
            HostName=$d.HOSTNAME
            Kernel=$d.KERNEL
            OS=$d.OS
            MetadataExists=($d.EXISTS -eq '1')
            FileChecksum=$d.FILECKSUM
            Content=$content
            Tags=$tags
        }
    } finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
}

# Creates linux Metadata Content for the calling workflow.
function New-LinuxMetadataContent {
    param(
        [AllowEmptyString()][string]$ExistingContent,
        [bool]$MetadataExists,
        [Parameter(Mandatory)][string]$Action,
        [AllowEmptyString()][string]$DesiredTags
    )

    if(-not $MetadataExists){
        if($Action -eq 'Clear'){ return '' }
        return "TAGS=$DesiredTags`n"
    }

    $normalized=$ExistingContent -replace "`r`n","`n" -replace "`r","`n"
    $hadFinalNewline=$normalized.EndsWith("`n")
    $lines=@($normalized -split "`n")
    if($hadFinalNewline -and $lines.Count -gt 0 -and $lines[-1] -eq ''){
        if($lines.Count -eq 1){$lines=@()}else{$lines=$lines[0..($lines.Count-2)]}
    }

    $result=New-Object System.Collections.Generic.List[string]
    $tagHandled=$false

    foreach($line in $lines){
        if($line -match '^TAGS='){
            if(-not $tagHandled){
                if($Action -ne 'Clear'){[void]$result.Add("TAGS=$DesiredTags")}
                $tagHandled=$true
            }
        } else {
            [void]$result.Add($line)
        }
    }

    $appended=$false
    if(($Action -ne 'Clear') -and (-not $tagHandled)){
        [void]$result.Add("TAGS=$DesiredTags")
        $appended=$true
    }

    $text=$result -join "`n"
    if(($hadFinalNewline -or $appended) -and $text.Length -gt 0){$text+="`n"}
    return $text
}

# Runs linux Write for the calling workflow.
function Invoke-LinuxWrite {
    param(
        [Parameter(Mandatory)][string]$Ssh,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$User,
        [Parameter(Mandatory)][string]$ExpectedChecksum,
        [Parameter(Mandatory)][bool]$ExpectedExists,
        [AllowEmptyString()][string]$DesiredTags,
        [AllowEmptyString()][string]$NewContent
    )

    $MetadataFile = (Get-HVModuleConfiguration).LinuxMetadataFile
    $metadataBase = [IO.Path]::GetFileName($MetadataFile)
    $stageName=".$metadataBase.$([Guid]::NewGuid().ToString('N'))"
    $etcTempName=".$metadataBase.$([Guid]::NewGuid().ToString('N')).tmp"
    $contentB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($NewContent))
    $existsFlag=if($ExpectedExists){'1'}else{'0'}

    # Deliberately a flat remote command: no embedded shell program and no
    # sudo /bin/sh -c. The complete desired file is staged as the SSH user.
    $remoteCommand=@"
stage=`"`$HOME/$stageName`"; file=$MetadataFile; etmp=/etc/$etcTempName; cleanup(){ rm -f `"`$stage`"; }; trap cleanup EXIT HUP INT TERM; printf '%s' '$contentB64' | base64 -d > `"`$stage`" || exit 50; if [ '$existsFlag' = '1' ]; then [ -e `"`$file`" ] || { echo 'ERROR: metadata file disappeared after SSH #1. No changes were made.'; exit 47; }; set -- `$(cksum `"`$file`"); actual=`"`$1:`$2`"; [ `"`$actual`" = '$ExpectedChecksum' ] || { echo 'ERROR: metadata changed after SSH #1. No changes were made.'; exit 47; }; else [ ! -e `"`$file`" ] || { echo 'ERROR: metadata file appeared after SSH #1. No changes were made.'; exit 47; }; fi; scount=`$(grep -c '^TAGS=' `"`$stage`" 2>/dev/null || true); [ `"`$scount`" -le 1 ] || { echo 'ERROR: staged metadata contains duplicate TAGS lines.'; exit 51; }; echo ''; echo 'sudo is required to install the validated metadata file.'; if [ -e `"`$file`" ]; then sudo cp -p `"`$file`" `"`$etmp`" || exit 52; cat `"`$stage`" | sudo tee `"`$etmp`" >/dev/null || { sudo rm -f `"`$etmp`"; exit 53; }; else cat `"`$stage`" | sudo tee `"`$etmp`" >/dev/null || exit 53; sudo chmod 0644 `"`$etmp`" || { sudo rm -f `"`$etmp`"; exit 54; }; sudo chown root:root `"`$etmp`" || { sudo rm -f `"`$etmp`"; exit 55; }; fi; sudo mv -f `"`$etmp`" `"`$file`" || { sudo rm -f `"`$etmp`"; exit 56; }; vcount=`$(grep -c '^TAGS=' `"`$file`" 2>/dev/null || true); [ `"`$vcount`" -le 1 ] || { echo 'ERROR: post-write verification found duplicate TAGS lines.'; exit 46; }; if [ -z '$DesiredTags' ]; then if grep -q '^TAGS=' `"`$file`"; then echo 'ERROR: post-write verification failed: TAGS line still exists after Clear.'; exit 46; fi; echo ''; echo 'Linux-side verification succeeded.'; echo 'Verified tags: <none>'; exit 0; fi; [ `"`$vcount`" -eq 1 ] || { echo 'ERROR: post-write verification failed: TAGS line is missing.'; exit 46; }; verified=`$(grep '^TAGS=' `"`$file`" | head -n 1 | sed 's/^TAGS=//' | tr '[:lower:]' '[:upper:]'); case `"`$verified`" in '$DesiredTags') ;; *) echo 'ERROR: post-write verification mismatch.'; echo `"Expected: $DesiredTags`"; echo `"Read back: `$verified`"; exit 46 ;; esac; echo ''; echo 'Linux-side verification succeeded.'; echo `"Verified tags: `$verified`"; exit 0
"@

    Write-Host ""
    Write-Host "SSH #2 will now perform the protected update."
    Write-Host "Enter the SSH password again; sudo will then request the Linux password."
    Write-Host ""
    Write-Verbose "SSH #2: forced PTY (-tt), user staging, concurrency re-check, narrow sudo install, and verification."
    Write-Verbose "Staging file: ~/$stageName"
    Write-Verbose "Only '$MetadataFile' may be replaced."

    & $Ssh -tt -o ConnectTimeout=10 -o ServerAliveInterval=10 -o ServerAliveCountMax=2 "$User@$Target" $remoteCommand
    $rc=$LASTEXITCODE

    switch($rc){
        0  {return}
        46 {throw "Write completed but Linux-side verification did not match the requested tags. Manual review is required."}
        47 {throw "Write aborted because the metadata changed between SSH #1 and SSH #2. No overwrite was attempted."}
        50 {throw "Unable to create the user staging file from the prepared metadata."}
        51 {throw "The staged metadata failed validation. No /etc change was attempted."}
        52 {throw "Unable to create the protected /etc temporary file while preserving existing ownership/mode."}
        53 {throw "Unable to write the staged content to the protected /etc temporary file."}
        54 {throw "Unable to set mode 0644 on a new metadata file."}
        55 {throw "Unable to set root:root ownership on a new metadata file."}
        56 {throw "Unable to atomically install the protected metadata file."}
        default {throw "SSH #2/Linux update failed with exit code $rc."}
    }
}

# Runs physical Linux Tag Operation for the calling workflow.
function Invoke-PhysicalLinuxTagOperation {
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][string]$UserName,
        [Parameter(Mandatory)][ValidateSet('Get','Add','Remove','Set','ReplaceAll','Clear')]
        [string]$Action,
        [string[]]$RequestedTags,
        [switch]$ValidateOnly
    )

    $MetadataFile = (Get-HVModuleConfiguration).LinuxMetadataFile

    if ((Test-IsPowerShellISE) -and (-not $ConsoleRelaunched)) {
        throw "PhysicalLinux tagging must be run from a standard PowerShell console, not PowerShell ISE."
    }

    $Ssh = (Get-Command ssh.exe -ErrorAction SilentlyContinue).Source
    if (-not $Ssh) {
        throw "Windows OpenSSH client (ssh.exe) was not found."
    }

    Write-Verbose "OpenSSH client: $Ssh"

    $Target = Resolve-LinuxTarget -Name $ComputerName

    $Discovery = Invoke-LinuxDiscovery `
        -Ssh $Ssh `
        -Target $Target.Target `
        -User $UserName

    $CurrentTags = @($Discovery.Tags)
    $DesiredTags = @(
        Get-DesiredTags `
            -ExistingTags $CurrentTags `
            -Action $Action `
            -RequestedTags $RequestedTags
    )

    $CurrentTagString = $CurrentTags -join ';'
    $DesiredTagString = $DesiredTags -join ';'
    $DisplayCurrentTags = Format-HVReadableTags -Tags $CurrentTags
    $DisplayDesiredTags = Format-HVReadableTags -Tags $DesiredTags
    $Changed = -not (Test-HVTagSetEqual -Left $CurrentTags -Right $DesiredTags)

    if ($Action -eq 'Get') {
        [pscustomobject]@{
            ComputerName   = $ComputerName
            Type           = 'PhysicalLinux'
            AccessMethod   = 'SSH'
            UserName       = $UserName
            ResolvedDnsName= $Target.Dns
            IPAddress      = $Target.IP
            LinuxHostName  = $Discovery.HostName
            OS             = $Discovery.OS
            Kernel         = $Discovery.Kernel
            MetadataFile   = $MetadataFile
            MetadataExists = $Discovery.MetadataExists
            Action         = 'Get'
            Tags           = $DisplayCurrentTags
            Status         = 'Success'
        } | Format-List
        return
    }

    if (-not $Changed -or $ValidateOnly) {
        [pscustomobject]@{
            ComputerName = $ComputerName
            Type         = 'PhysicalLinux'
            AccessMethod = 'SSH'
            UserName     = $UserName
            Action       = $Action
            PreviousTags = $DisplayCurrentTags
            Tags         = $DisplayDesiredTags
            Changed      = $Changed
            ValidateOnly = [bool]$ValidateOnly
            Status       = 'Success'
        } | Format-List

        if (-not $Changed) {
            Write-Host "No tag changes are required."
        }
        else {
            Write-Host "VALIDATE ONLY - No changes were made."
        }
        return
    }

    Write-Host ""
    Write-Host "Modification summary:"
    Write-Host "  Current tags : $DisplayCurrentTags"
    Write-Host "  New tags     : $DisplayDesiredTags"
    Write-Host ""

    $NewContent = New-LinuxMetadataContent `
        -ExistingContent $Discovery.Content `
        -MetadataExists $Discovery.MetadataExists `
        -Action $Action `
        -DesiredTags $DesiredTagString

    Invoke-LinuxWrite `
        -Ssh $Ssh `
        -Target $Target.Target `
        -User $UserName `
        -ExpectedChecksum $Discovery.FileChecksum `
        -ExpectedExists $Discovery.MetadataExists `
        -DesiredTags $DesiredTagString `
        -NewContent $NewContent

    [pscustomobject]@{
        ComputerName = $ComputerName
        Type         = 'PhysicalLinux'
        AccessMethod = 'SSH'
        UserName     = $UserName
        Action       = $Action
        PreviousTags = $DisplayCurrentTags
        Tags         = $DisplayDesiredTags
        Changed      = $true
        ValidateOnly = $false
        Status       = 'Success'
    } | Format-List

    Write-Host "Tags updated successfully."
}

