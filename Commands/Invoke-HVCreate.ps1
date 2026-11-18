# Purpose: Invoke-HVCreate - command entry point.
# Maintains the existing validation, logging, and execution behavior.

# Validates the requested VM definitions, reports the plan, then creates VMs and registers cluster roles.
function Invoke-HVCreate {
    [CmdletBinding()]
    param(
        [Parameter(Position=0)][string]$ConfigFile,
        [string]$TargetHost,
        [switch]$ValidateOnly,
        [switch]$AllowDuplicateBaseVMName,
        [switch]$ShowTiming,
        [switch]$Help
    )
    if ($Help -or $ConfigFile -eq '/?' -or ($args -contains '/?')) { Show-HVUsageHelp; return }
    if ([string]::IsNullOrWhiteSpace($ConfigFile)) {
        throw 'Invalid or missing parameter: -ConfigFile is required. Use hv-create -Help for help.'
    }
    if (-not (Test-Path -LiteralPath $ConfigFile -PathType Leaf)) {
        throw "VM configuration file not found: $ConfigFile"
    }
    # Own the transcript at the public command boundary so the timing report is captured.
    # New-HVVM retains its original standalone logging path when invoked without -ExternalTranscript.
    $settings = Get-HyperVToolsSettings
    $logFile = Start-HVExecutionLog -ConfigFilePath $ConfigFile -LogDirectory $settings.LogPath -StandardName
    # VM creation workflow now resides in this command file.
    $transcriptStarted = $false
    try {
        Start-Transcript -LiteralPath $logFile -ErrorAction Stop | Out-Null
        $transcriptStarted = $true
        Write-Host "Create | Transcript: $logFile" -ForegroundColor Cyan
        Invoke-HVTiming -Action Reset -Enabled:$ShowTiming
        try {
            Invoke-HVTiming -Action Measure -TimingLabel 'VM creation workflow' -Target $TargetHost -ScriptBlock {
                Invoke-HVCreateWorkflow -ConfigFile $ConfigFile -TargetHost $TargetHost -ValidateOnly:$ValidateOnly -AllowDuplicateBaseVMName:$AllowDuplicateBaseVMName -ExternalTranscript
            }
        }
        finally {
            Invoke-HVTiming -Action Report
        }
    }
    finally {
        if ($transcriptStarted) { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null }
    }

}


# Private implementation, kept with the public Create command.
function Invoke-HVCreateWorkflow {
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$ConfigFile,

    [string]$TargetHost,

    [switch]$ValidateOnly,

    # Allows creating another VM whose short name already appears
    # in an existing VM display name or repeats in this config file.
    # Target display names must still be unique.
    [switch]$AllowDuplicateBaseVMName,

    # Internal switch: public hv-create owns the transcript and timing report.
    [switch]$ExternalTranscript,

    [switch]$Help
)


if ($Help -or $ConfigFile -eq '/?' -or ($args -contains '/?')) {
    Show-HVUsageHelp
    return
}

if ([string]::IsNullOrWhiteSpace($ConfigFile)) {
    Show-HVUsageHelp
    Write-Host 'ERROR: -ConfigFile is required unless using /?.' -ForegroundColor Red
    return
}

# Shared toolkit configuration is separate from the VM definition (-ConfigFile).
# Expected repository layout: 000_HyperVTools_Config and 001_CreateVM are siblings.


$HyperVToolsSettings = Get-HyperVToolsSettings
$script:HyperVToolsLogPath = $HyperVToolsSettings.LogPath
$script:ShortVMNamePattern = $HyperVToolsSettings.ShortNamePattern


$LogFilePath = $null
if (-not $ExternalTranscript) {
    try {
        $LogFilePath = Start-HVExecutionLog -ConfigFilePath $ConfigFile -LogDirectory $HyperVToolsSettings.LogPath
        Start-Transcript -Path $LogFilePath -Force | Out-Null
    }
    catch {
        Write-Warning "Could not start transcript log file '$LogFilePath'. $($_.Exception.Message)"
    }
}


$createHelperNames = @('Ensure-HVDirectory','Remove-EmptyDirectoryTreeSafe','Invoke-GrowVhdIfNeeded','Prepare-DiskPath')
# Transfer complete function source files, rather than rebuilding functions from
# Get-Command.Definition. This keeps each param block inside its function.
$createFunctionRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'CommandSpecific\Create'
$createSourceFiles = @($createHelperNames + 'New-HVVMFromTemplate' | ForEach-Object {
    $sourcePath = Join-Path $createFunctionRoot ($_.ToString() + '.ps1')
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "Missing Create function file: $sourcePath" }
    Get-Content -LiteralPath $sourcePath -Raw -ErrorAction Stop
})
$remoteCreateDefinitions = $createSourceFiles -join "`n"
# Invoke the already imported module function directly for local execution.


$ValidationErrors   = New-Object System.Collections.ArrayList
$ValidationWarnings = New-Object System.Collections.ArrayList

if (-not (Test-IsElevated)) {
    throw "This script must be run in elevated PowerShell (Run as Administrator) on the target Hyper-V host."
}

# Parse and validate VM groups before resolving hosts or creating any resources.
# A shared VM Parameters block cannot use FolderNameOverride.
try {
    $sections = Read-HVVMConfig -Path $ConfigFile
}
catch {
    $parseMessage = $_.Exception.Message
    if ($parseMessage -match '^FolderNameOverride .* is allowed only for a SINGLE VM per VM Parameters section\.') {
        Write-Host ''
        Write-Host 'Validation FAILED. No VMs were created.' -ForegroundColor Yellow
        Write-Host (" - {0}" -f $parseMessage) -ForegroundColor Red
        Stop-TranscriptSafe -KeepTranscript:$ExternalTranscript
        return
    }
    throw
}
$parsedItems = @()
$SeenBaseVMNames = @{}
$SeenTargetDisplayVMNames = @{}

foreach ($section in $sections) {
    $vmBlock    = $section.VM
    $paramBlock = $section.Params

    # Validate proposed tags for this VM before any creation begins.
    $CreateTags = @()
    foreach ($TagCategory in @('Scope','Env','App','Role','Contact')) {
        if (-not $vmBlock.ContainsKey($TagCategory)) { continue }
        foreach ($TagValue in @(([string]$vmBlock[$TagCategory]) -split ';')) {
            if (-not [string]::IsNullOrWhiteSpace($TagValue)) {
                $CreateTags += ('{0}:{1}' -f $TagCategory,$TagValue.Trim())
            }
        }
    }
    if ($CreateTags.Count -gt 0) {
        try {
            if ($null -eq $CreateTagCatalog) {
                $CreateTagCatalog = Read-HVTagCatalog -Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'Config/ServerTags.config.txt')
            }
            $CreateTags = @(Test-ApprovedTags -InputTags $CreateTags -Catalog $CreateTagCatalog)
            $CreateTags = @(ConvertTo-HVOrderedTags -Tags $CreateTags)
        }
        catch {
            Add-ValidationError -List $ValidationErrors -Message ("VM '{0}': invalid Tags: {1}" -f $vmBlock['VM Name'],$_.Exception.Message)
        }
    }
    $BaseVMName = ($vmBlock['VM Name']).Trim()
    $VMDescription = $vmBlock['VM Description']
    $TargetDisplayVMName = Get-HVDisplayVMName -BaseVMName $BaseVMName -VMDescription $VMDescription

    try { Test-HVShortVMName -BaseVMName $BaseVMName }
    catch { Add-ValidationError -List $ValidationErrors -Message $_.Exception.Message }

    if ($SeenBaseVMNames.ContainsKey($BaseVMName)) {
        if ($AllowDuplicateBaseVMName) {
            Add-ValidationWarning -List $ValidationWarnings -Message "Duplicate base VM Name in config file allowed by -AllowDuplicateBaseVMName: $BaseVMName. Target display names must still be unique."
        }
        else {
            Add-ValidationError -List $ValidationErrors -Message "Duplicate VM Name in config file: $BaseVMName. Use -AllowDuplicateBaseVMName only if descriptions make final display names unique."
        }
    }
    else {
        $SeenBaseVMNames[$BaseVMName] = $true
    }

    $targetKey = $TargetDisplayVMName.Trim().ToUpper()
    if ($SeenTargetDisplayVMNames.ContainsKey($targetKey)) {
        Add-ValidationError -List $ValidationErrors -Message "Duplicate target display VM name in config file: $TargetDisplayVMName"
    }
    else {
        $SeenTargetDisplayVMNames[$targetKey] = $true
    }

    $requiredKeys = @(
        'Destination', 'Generation', 'Enable S.Boot',
        'CPU Number', 'Memory Size', 'Enable Dyn.RAM',
        'Time Sync', 'Guest Services'
    )

    foreach ($key in $requiredKeys) {
        if (-not $paramBlock.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($paramBlock[$key])) {
            Add-ValidationError -List $ValidationErrors -Message "VM '$BaseVMName': missing required config field '$key'."
        }
    }

    try {
        $ClusteredRaw    = Convert-HVYesNo -Value $paramBlock['Clustered']      -FieldName 'Clustered'
        $Clustered       = ($ClusteredRaw -eq $true)
        $SecureBoot      = Convert-HVYesNo -Value $paramBlock['Enable S.Boot']  -FieldName 'Enable S.Boot'
        $DynamicRam      = Convert-HVYesNo -Value $paramBlock['Enable Dyn.RAM'] -FieldName 'Enable Dyn.RAM'
        $TimeSyncEnabled = Convert-HVYesNo -Value $paramBlock['Time Sync']      -FieldName 'Time Sync'
        $GuestSvcEnabled = Convert-HVYesNo -Value $paramBlock['Guest Services'] -FieldName 'Guest Services'

        $Generation   = [int]$paramBlock['Generation']
        $CpuCount     = [int]$paramBlock['CPU Number']
        $StartupRamMB = [int]$paramBlock['Memory Size']

        if ($DynamicRam) {
            if (-not $paramBlock.ContainsKey('Min RAM') -or
                [string]::IsNullOrWhiteSpace($paramBlock['Min RAM'])) {
                throw "Min RAM is required when Enable Dyn.RAM is set to Yes."
            }

            if (-not $paramBlock.ContainsKey('Max RAM') -or
                [string]::IsNullOrWhiteSpace($paramBlock['Max RAM'])) {
                throw "Max RAM is required when Enable Dyn.RAM is set to Yes."
            }

            $MinRamMB = [int]$paramBlock['Min RAM']
            $MaxRamMB = [int]$paramBlock['Max RAM']
        }
        else {
            # Min/Max RAM are not used when Dynamic Memory is disabled.
            $MinRamMB = $StartupRamMB
            $MaxRamMB = $StartupRamMB
        }

        $ConfiguredHyperVHost = $paramBlock['Hyper-V Host']
        $DestinationRoot      = $paramBlock['Destination']
        $FolderNameOverride = if ($paramBlock.ContainsKey('FolderNameOverride')) { [string]$paramBlock['FolderNameOverride'] } else { $null }
        if (-not [string]::IsNullOrWhiteSpace($FolderNameOverride)) {
            $folderValueTrimmed = $FolderNameOverride.Trim()
            if ($folderValueTrimmed -match '[\\/:*?"<>|]' -or $folderValueTrimmed -in @('.', '..') -or $folderValueTrimmed.EndsWith('.') -or [char]::IsWhiteSpace($folderValueTrimmed[$folderValueTrimmed.Length-1]) -or $folderValueTrimmed -match '[\x00-\x1F]' -or $folderValueTrimmed -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$') {
                Add-ValidationError -List $ValidationErrors -Message "VM '$BaseVMName': FolderNameOverride must be a single valid Windows folder name: $FolderNameOverride"
            }
        }
        $CSource              = if ($paramBlock.ContainsKey('C, Source')) { $paramBlock['C, Source'] } else { $null }
        $NetworkDefinitions   = Get-NetworkDefinitionsFromParams -ParamBlock $paramBlock
    }
    catch {
        Add-ValidationError -List $ValidationErrors -Message "VM '$BaseVMName': $($_.Exception.Message)"
        continue
    }

    if ($Generation -notin 1,2) {
        Add-ValidationError -List $ValidationErrors -Message "VM '$BaseVMName': Generation must be 1 or 2."
    }
    if ($CpuCount -lt 1) {
        Add-ValidationError -List $ValidationErrors -Message "VM '$BaseVMName': CPU Number must be at least 1."
    }
    if ($StartupRamMB -lt 32) {
        Add-ValidationError -List $ValidationErrors -Message "VM '$BaseVMName': Memory Size looks too small: $StartupRamMB MB"
    }
    if ($DynamicRam) {
        if ($MaxRamMB -lt $StartupRamMB) {
            Add-ValidationError -List $ValidationErrors -Message "VM '$BaseVMName': Max RAM ($MaxRamMB MB) cannot be lower than startup RAM ($StartupRamMB MB)."
        }

        if ($MinRamMB -gt $StartupRamMB) {
            Add-ValidationWarning -List $ValidationWarnings -Message "VM '$BaseVMName': Min RAM ($MinRamMB MB) is greater than startup RAM ($StartupRamMB MB). It will be adjusted to $StartupRamMB MB during execution."
            $MinRamMB = $StartupRamMB
        }
    }

    # Discover every one-letter disk defined in the config instead of limiting processing to C/D/E/F.
    # Supported examples: C, D, E, F, Z, S, K, etc.
    # C is always included because it is mandatory and must be validated even when missing.
    $diskLetters = @(
        $paramBlock.Keys |
            Where-Object { $_ -match '^([A-Z]),\s*(InPlace|Source|Move Src \(Move\)|Size|New Size Incr\.to|If Fixed \(Y\)|V\.Disks Folder|Dest\.Override)$' } |
            ForEach-Object { ([regex]::Match($_, '^([A-Z]),')).Groups[1].Value } |
            Sort-Object -Unique
    )

    if ($diskLetters -notcontains 'C') {
        $diskLetters = @('C') + $diskLetters
    }

    $diskDefinitions = @()
    foreach ($letter in $diskLetters) {
        $inPlaceKey   = "$letter, InPlace"
        $sourceKey    = "$letter, Source"
        $moveKey      = "$letter, Move Src (Move)"
        $sizeKey      = "$letter, Size"
        $incrKey      = "$letter, New Size Incr.to"
        $fixedKey     = "$letter, If Fixed (Y)"
        $folderKey    = "$letter, V.Disks Folder"
        $overrideKey  = "$letter, Dest.Override"

        $inPlaceValue = if ($paramBlock.ContainsKey($inPlaceKey)) { $paramBlock[$inPlaceKey] } else { $null }
        $sourceValue  = if ($paramBlock.ContainsKey($sourceKey)) { $paramBlock[$sourceKey] } else { $null }
        $moveValue    = if ($paramBlock.ContainsKey($moveKey)) { $paramBlock[$moveKey] } else { $null }
        $sizeGB       = if ($paramBlock.ContainsKey($sizeKey)) { Get-OptionalInt -Value $paramBlock[$sizeKey] } else { $null }
        $newSizeGB    = if ($paramBlock.ContainsKey($incrKey)) { Get-OptionalInt -Value $paramBlock[$incrKey] } else { $null }
        $isFixed      = if ($paramBlock.ContainsKey($fixedKey)) { Convert-HVYesNo -Value $paramBlock[$fixedKey] -FieldName $fixedKey } else { $null }
        $folderValue  = if ($paramBlock.ContainsKey($folderKey)) { $paramBlock[$folderKey] } else { $null }
        $overrideVal  = if ($paramBlock.ContainsKey($overrideKey)) { $paramBlock[$overrideKey] } else { $null }

        $hasInPlace = -not [string]::IsNullOrWhiteSpace($inPlaceValue)
        $hasSource  = -not [string]::IsNullOrWhiteSpace($sourceValue)
        $hasSize    = $null -ne $sizeGB
        $hasMove    = -not [string]::IsNullOrWhiteSpace($moveValue)

        $action = $null
        $isDefined = $false
        if ($hasInPlace) {
            $action = 'InPlace'
            $isDefined = $true

            if ($hasSource) { Add-ValidationWarning -List $ValidationWarnings -Message "VM '$BaseVMName': $sourceKey is ignored because $inPlaceKey is specified." }
            if ($hasMove)   { Add-ValidationWarning -List $ValidationWarnings -Message "VM '$BaseVMName': $moveKey is ignored because $inPlaceKey is specified." }
            if ($hasSize)   { Add-ValidationWarning -List $ValidationWarnings -Message "VM '$BaseVMName': $sizeKey is ignored because $inPlaceKey is specified. Use $incrKey only to grow." }
            if ($null -ne $isFixed) { Add-ValidationWarning -List $ValidationWarnings -Message "VM '$BaseVMName': $fixedKey is ignored because $inPlaceKey is specified." }
            if (-not [string]::IsNullOrWhiteSpace($folderValue)) { Add-ValidationWarning -List $ValidationWarnings -Message "VM '$BaseVMName': $folderKey is ignored because $inPlaceKey is specified." }
            if (-not [string]::IsNullOrWhiteSpace($overrideVal)) { Add-ValidationWarning -List $ValidationWarnings -Message "VM '$BaseVMName': $overrideKey is ignored because $inPlaceKey is specified." }

            $destinationVmFolder = Get-EffectiveVmFolderFromDestination -DestinationRoot $DestinationRoot -BaseVMName $BaseVMName -FolderNameOverride $FolderNameOverride
            $inPlaceVmFolder     = Get-EffectiveVmFolderFromInPlaceDisk -InPlacePath $inPlaceValue
            if (-not [string]::IsNullOrWhiteSpace($destinationVmFolder) -and
                -not [string]::IsNullOrWhiteSpace($inPlaceVmFolder) -and
                $destinationVmFolder.ToUpper() -ne $inPlaceVmFolder.ToUpper()) {
                Add-ValidationWarning -List $ValidationWarnings -Message "VM '$BaseVMName': $inPlaceKey places/uses VM folder '$inPlaceVmFolder', but Destination + VM Name resolves to '$destinationVmFolder'. Confirm this is intentional."
            }

            $nameHints = Get-VmNameHintsFromPath -PathValue $inPlaceValue -BaseVMName $BaseVMName
            foreach ($hint in $nameHints) {
                Add-ValidationWarning -List $ValidationWarnings -Message "VM '$BaseVMName': $inPlaceKey path appears to belong to VM/folder '$hint'. Confirm this is intentional: $($inPlaceValue.Trim())"
            }
        }
        elseif ($hasSource) {
            if ($hasMove -and $moveValue.Trim().ToLower() -eq 'move') {
                $action = 'MoveSource'
            }
            else {
                $action = 'CopySource'
                if ($hasMove) {
                    Add-ValidationWarning -List $ValidationWarnings -Message "VM '$BaseVMName': $moveKey value '$moveValue' is not 'Move'; source disk $letter will be copied."
                }
            }
            $isDefined = $true

            if ($hasSize) { Add-ValidationWarning -List $ValidationWarnings -Message "VM '$BaseVMName': $sizeKey is ignored because $sourceKey is specified. Use $incrKey only to grow after copy/move." }
            if ($null -ne $isFixed) { Add-ValidationWarning -List $ValidationWarnings -Message "VM '$BaseVMName': $fixedKey is ignored because $sourceKey is specified. Source VHDX type will be preserved." }
        }
        elseif ($hasSize) {
            $action = 'New'
            $isDefined = $true
            if ($null -ne $newSizeGB) {
                Add-ValidationWarning -List $ValidationWarnings -Message "VM '$BaseVMName': $incrKey is ignored for newly created disk $letter. Use $sizeKey for new disk size."
            }
            if ($hasMove) {
                Add-ValidationWarning -List $ValidationWarnings -Message "VM '$BaseVMName': $moveKey is ignored because $sourceKey is empty."
            }
        }
        else {
            if ($hasMove) {
                Add-ValidationWarning -List $ValidationWarnings -Message "VM '$BaseVMName': $moveKey is ignored because neither $inPlaceKey nor $sourceKey is specified."
            }
            if ($null -ne $newSizeGB) {
                Add-ValidationWarning -List $ValidationWarnings -Message "VM '$BaseVMName': $incrKey is ignored because disk $letter is not defined."
            }
        }

        $layout = Get-ResolvedDiskLayout -BaseVMName $BaseVMName -DestinationRoot $DestinationRoot -Letter $letter -DiskSubfolder $folderValue -DestinationOverride $overrideVal -InPlacePath $inPlaceValue -FolderNameOverride $FolderNameOverride
        $diskDefinitions += [pscustomobject]@{
            Letter          = $letter
            IsDefined       = $isDefined
            Action          = $action
            InPlace         = if ($hasInPlace) { $inPlaceValue.Trim() } else { $null }
            Source          = if ($hasSource) { $sourceValue.Trim() } else { $null }
            MoveRaw         = $moveValue
            SizeGB          = $sizeGB
            NewSizeIncrToGB = $newSizeGB
            IsFixed         = $isFixed
            FolderRaw       = $folderValue
            OverrideRaw     = $overrideVal
            Layout          = $layout
        }
    }

    $diskC = $diskDefinitions | Where-Object { $_.Letter -eq 'C' } | Select-Object -First 1
    if (-not $diskC.IsDefined) {
        Add-ValidationError -List $ValidationErrors -Message "VM '$BaseVMName': specify one of 'C, InPlace', 'C, Source', or 'C, Size'."
    }
    foreach ($diskDef in ($diskDefinitions | Where-Object { $_.IsDefined })) {
        if ($diskDef.Action -eq 'New' -and ($null -eq $diskDef.SizeGB -or $diskDef.SizeGB -le 0)) {
            Add-ValidationError -List $ValidationErrors -Message "VM '$BaseVMName': Disk $($diskDef.Letter) size must be greater than 0 for new disk creation."
        }
        if ($null -ne $diskDef.NewSizeIncrToGB -and $diskDef.NewSizeIncrToGB -le 0) {
            Add-ValidationError -List $ValidationErrors -Message "VM '$BaseVMName': Disk $($diskDef.Letter), New Size Incr.to must be greater than 0 when specified."
        }
        if ($diskDef.Action -ne 'InPlace' -and -not [string]::IsNullOrWhiteSpace($diskDef.OverrideRaw)) {
            $overrideTrimmed = $diskDef.OverrideRaw.Trim()
            if ([string]::IsNullOrWhiteSpace((Split-Path -Path $overrideTrimmed -Parent))) {
                Add-ValidationError -List $ValidationErrors -Message "VM '$BaseVMName': Disk $($diskDef.Letter), Dest.Override must be a full VHDX path, not only a file name: $overrideTrimmed"
            }
            if ($overrideTrimmed -notmatch '\.vhdx$') {
                Add-ValidationWarning -List $ValidationWarnings -Message "VM '$BaseVMName': Disk $($diskDef.Letter), Dest.Override does not end with .vhdx: $overrideTrimmed"
            }
        }
    }

    foreach ($net in $NetworkDefinitions) {
        if ($null -ne $net.VlanId -and ($net.VlanId -lt 1 -or $net.VlanId -gt 4094)) {
            Add-ValidationError -List $ValidationErrors -Message "VM '$BaseVMName': VLAN_$($net.Index) must be between 1 and 4094."
        }
        if ($null -ne $net.VlanId -and [string]::IsNullOrWhiteSpace($net.SwitchName)) {
            Add-ValidationWarning -List $ValidationWarnings -Message "VM '$BaseVMName': VLAN_$($net.Index) is specified, but Network_$($net.Index) is blank. Adapter will be created disconnected, then VLAN $($net.VlanId) will still be applied to that adapter."
        }
    }


    $parsedItems += [pscustomobject]@{
        BaseVMName          = $BaseVMName
        VMDescription       = $VMDescription
        TargetDisplayVMName = $TargetDisplayVMName
        HyperVHost          = $ConfiguredHyperVHost
        Clustered           = $Clustered
        DestinationRoot     = $DestinationRoot
        FolderNameOverride = $FolderNameOverride
        Generation          = $Generation
        SecureBoot          = $SecureBoot
        CpuCount            = $CpuCount
        StartupRamMB        = $StartupRamMB
        DynamicRam          = $DynamicRam
        MinRamMB            = $MinRamMB
        MaxRamMB            = $MaxRamMB
        TimeSyncEnabled     = $TimeSyncEnabled
        GuestSvcEnabled     = $GuestSvcEnabled
        CSource             = $CSource
        CSizeGB             = $diskC.SizeGB
        DiskDefinitions     = $diskDefinitions
        NetworkDefinitions  = $NetworkDefinitions
        CreateTags          = @($CreateTags)
    }
}

if ($ValidationErrors.Count -gt 0) {
    Write-Host ""
    Write-Host "Validation FAILED. No VMs were created." -ForegroundColor Yellow
    foreach ($err in $ValidationErrors) { Write-Host " - $err" -ForegroundColor Red }
    Stop-TranscriptSafe -KeepTranscript:$ExternalTranscript
    return
}

# Config host or optional override may identify a Hyper-V node OR a cluster.
$configHosts = @($parsedItems | ForEach-Object { if ($_.HyperVHost) { $_.HyperVHost.Trim() } } | Select-Object -Unique)
if ($configHosts.Count -gt 1) { throw "Multiple Hyper-V hosts/clusters in one config are not supported: $($configHosts -join ', ')." }
$configHost = if ($configHosts.Count) { $configHosts[0] } else { $null }
$effectiveHost = if ($TargetHost) { $TargetHost.Trim() } else { $configHost }
if (-not $effectiveHost) { throw 'No Hyper-V host/cluster specified in config or -TargetHost.' }
if ($TargetHost -and $configHost -and $TargetHost.Trim() -ine $configHost) {
    Write-Host ''
    Write-Warning 'Target host differs from configuration file.'
    Write-Host ("Configuration TargetHost : {0}" -f $configHost)
    Write-Host ("Command-line TargetHost  : {0}" -f $TargetHost.Trim())
    Write-Host ''
    Write-Host ("  1. Override destination with {0}" -f $TargetHost.Trim())
    Write-Host ("  2. Continue using configuration value {0}" -f $configHost)
    Write-Host '  3. Cancel and quit'
    do { $selection = (Read-Host 'Selection [1-3]').Trim() } while ($selection -notin @('1','2','3'))
    switch ($selection) {
        '1' { $effectiveHost = $TargetHost.Trim() }
        '2' { $effectiveHost = $configHost }
        '3' { Write-Host 'Cancelled. No VM changes made.' -ForegroundColor Yellow; Stop-TranscriptSafe -KeepTranscript:$ExternalTranscript; return }
    }
    Write-Host ("Selected destination: {0}" -f $effectiveHost) -ForegroundColor Cyan
}


$clusterInfo = Get-HVTargetType -Name $effectiveHost -Items $parsedItems
$clusterName = $null
if ($clusterInfo) {
    $clusterName = $clusterInfo.ClusterName
    $candidates = @()
    foreach ($node in $clusterInfo.Nodes) {
        try {
            $capacity = Invoke-Command -ComputerName $node -ErrorAction Stop -ScriptBlock {
                $os = Get-CimInstance Win32_OperatingSystem
                $cpu = @(Get-CimInstance Win32_Processor | Measure-Object NumberOfLogicalProcessors -Sum).Sum
                $allocated = @(Get-VM | Where-Object State -eq 'Running' | Get-VMProcessor | Measure-Object Count -Sum).Sum
                [pscustomobject]@{
                    Node=$env:COMPUTERNAME; FreeRamMB=[math]::Floor($os.FreePhysicalMemory / 1024)
                    LogicalCpu=[int]$cpu; RunningVcpu=[int]$allocated
                }
            }
            $candidates += $capacity
        } catch { Write-Warning "Cluster node $node unavailable for capacity assessment: $($_.Exception.Message)" }
    }
    $ramRequired = [double](($parsedItems | Measure-Object StartupRamMB -Sum).Sum)
    $cpuRequired = [int](($parsedItems | Measure-Object CpuCount -Sum).Sum)
    # CPU is a relative headroom estimate (logical CPUs minus running vCPUs), not a hard allocation limit.
    $eligible = @($candidates | Where-Object { $_.FreeRamMB -ge $ramRequired })
    if (-not $eligible.Count) { throw "No reachable cluster node has enough free physical RAM ($ramRequired MB required)." }
    $chosen = $eligible | Sort-Object @{Expression={ $_.FreeRamMB - $ramRequired };Descending=$true}, @{Expression={ $_.LogicalCpu - $_.RunningVcpu - $cpuRequired };Descending=$true} | Select-Object -First 1
    Write-Host "Cluster detected: $clusterName" -ForegroundColor Cyan
    $candidates | Format-Table Node,FreeRamMB,LogicalCpu,RunningVcpu -AutoSize | Out-Host
    Write-Host "Selected node: $($chosen.Node) (RAM-first, CPU-headroom tie-break)" -ForegroundColor Green
    $effectiveHost = $chosen.Node
    if (@($parsedItems | Where-Object Clustered).Count -gt 0) {
        foreach ($item in $parsedItems | Where-Object Clustered) {
            if ($item.DestinationRoot -notmatch '^[a-zA-Z]:\\ClusterStorage\\') {
                throw "Clustered VM '$($item.BaseVMName)' must use a shared CSV destination under C:\ClusterStorage."
            }
        }
    }
} elseif (@($parsedItems | Where-Object Clustered).Count -gt 0) {
    # A node name is also valid; resolve its owning cluster.
    try {
        $clusterName = Invoke-Command -ComputerName $effectiveHost -ErrorAction Stop -ScriptBlock {
            Import-Module FailoverClusters -ErrorAction Stop
            (Get-Cluster -ErrorAction Stop).Name
        }
    } catch { throw "Clustered=Yes but cannot identify a cluster for '$effectiveHost': $($_.Exception.Message)" }
}
$isLocal = Test-LocalHostName $effectiveHost
$session = $null
if (-not $isLocal) {
    try {
        $session = New-PSSession -ComputerName $effectiveHost -ErrorAction Stop
        Invoke-Command -Session $session -ErrorAction Stop -ScriptBlock {
            Import-Module Hyper-V -ErrorAction Stop
            $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $principal = New-Object Security.Principal.WindowsPrincipal($identity)
            if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                throw 'Remote session is not elevated / does not have administrator rights.'
            }
        }
    } catch {
        if ($session) { Remove-PSSession $session }
        throw "Cannot initialize target host '$effectiveHost': $($_.Exception.Message)"
    }
} else { Import-Module Hyper-V -ErrorAction Stop }
Write-Host "Execution mode: $(if ($isLocal) {'LOCAL'} else {'REMOTE'}) ($effectiveHost)" -ForegroundColor Cyan

# Transfer exact v3.6 host-side validation functions into the remote session.
# Remote Create function source was assembled above from the original .ps1 files.

# Step 0.2: cluster-wide name inventory is collected from the jump host,
# regardless of whether the cluster name or a member node was configured.
# Inventory failures are fatal; never interpret an inaccessible node as vacant.
$nameInventory = @(Get-HVCreateNameInventory -TargetHost $effectiveHost -ClusterName $clusterName)
Write-Host ("Name inventory: {0} VM(s) across {1}." -f $nameInventory.Count, $(if ($clusterName) { "cluster '$clusterName'" } else { "standalone host '$effectiveHost'" })) -ForegroundColor Cyan
$validationFunctions = @('Test-HostEnvironmentLocal', 'Test-PathCreatableLocal', 'Get-VhdVirtualSizeBytesSafe', 'Test-PathStringSegments', 'Test-HVVMFolderVacancy')
$remoteValidationDefinitions = ($validationFunctions | ForEach-Object {
    "function $_ {" + (Get-Command $_ -CommandType Function).Definition + "}`n"
}) -join "`n"
$requiresNameConfirmation = $false
foreach ($item in $parsedItems) {
    $nameResult = Test-HVVMNameVacancy -BaseVMName $item.BaseVMName -TargetDisplayVMName $item.TargetDisplayVMName -Inventory $nameInventory -AllowDuplicateBaseVMName:$AllowDuplicateBaseVMName
    foreach ($err in $nameResult.Errors) {
        Add-ValidationError -List $ValidationErrors -Message "VM '$($item.TargetDisplayVMName)': $err"
    }
    foreach ($warn in $nameResult.Warnings) {
        Add-ValidationWarning -List $ValidationWarnings -Message "VM '$($item.TargetDisplayVMName)': $warn"
    }
    if (@($nameResult.Matches).Count -gt 0) { $requiresNameConfirmation = $true }
    if ($isLocal) {
        $envResult = Test-HostEnvironmentLocal -Item $item
    }
    else {
        $envResult = Invoke-Command -Session $session -ErrorAction Stop -ArgumentList @($remoteValidationDefinitions,$item) -ScriptBlock {
            param([string]$defs,[object]$vm)
            . ([scriptblock]::Create($defs))
            Test-HostEnvironmentLocal -Item $vm
        }
    }
    foreach ($err in $envResult.Errors) {
        Add-ValidationError -List $ValidationErrors -Message "VM '$($item.BaseVMName)': $err"
    }
    foreach ($warn in $envResult.Warnings) {
        Add-ValidationWarning -List $ValidationWarnings -Message "VM '$($item.BaseVMName)': $warn"
    }
}

if ($ValidationWarnings.Count -gt 0) {
    Write-Host ""
    Write-Host "Validation warnings:" -ForegroundColor Yellow
    foreach ($warning in $ValidationWarnings) { Write-Host " - $warning" -ForegroundColor Yellow }
}

if ($ValidationErrors.Count -gt 0) {
    Write-Host ""
    Write-Host "Validation FAILED. No VMs were created." -ForegroundColor Yellow
    foreach ($err in $ValidationErrors) { Write-Host " - $err" -ForegroundColor Red }
    Stop-TranscriptSafe -KeepTranscript:$ExternalTranscript
    return
}

Write-Host ""
Write-HVMessage -Message "Validation OK - no errors found." -ForegroundColor Green
Write-Host "Execution mode: $(if ($isLocal) {"LOCAL"} else {"REMOTE"}) ($effectiveHost)" -ForegroundColor Cyan
if ($AllowDuplicateBaseVMName) { Write-Host "Duplicate base VM-name mode: ALLOWED (target display name must still be unique)" -ForegroundColor Yellow }

Show-HVCreateReport -Items $parsedItems

if ($ValidateOnly) {
    Write-Host "ValidateOnly mode - no VM changes will be performed." -ForegroundColor Cyan
    Stop-TranscriptSafe -KeepTranscript:$ExternalTranscript
    return
}

# Explicit approval for any existing name candidate, including allowed Exact duplicates.
# N skips this entire batch (no partial creation); Q stops the batch.
if ($requiresNameConfirmation) {
    Write-Host 'Existing VM name candidates were found. Confirm before creating this batch.' -ForegroundColor Yellow
    do { $answer = (Read-Host 'Proceed with creation? [Y/N/Q]').Trim().ToUpperInvariant() } while ($answer -notin @('Y','YES','N','NO','Q','QUIT'))
    if ($answer -notin @('Y','YES')) {
        Write-Host 'Creation cancelled. No VMs created.' -ForegroundColor Yellow
        Stop-TranscriptSafe -KeepTranscript:$ExternalTranscript
        return
    }
}

# Apply mode follows the original pre-module behavior: absence of -ValidateOnly.

$moveDisks = @($parsedItems | ForEach-Object {
    $vmNameForMove = $_.BaseVMName
    $_.DiskDefinitions | Where-Object { $_.IsDefined -and $_.Action -eq 'MoveSource' } | ForEach-Object {
        [pscustomobject]@{ VMName = $vmNameForMove; Letter = $_.Letter; Source = $_.Source; Destination = $_.Layout.DiskPath }
    }
})

if ($moveDisks.Count -gt 0) {
    Write-Host ""
    Write-Host "MOVE SOURCE DISK CONFIRMATION REQUIRED" -ForegroundColor Yellow
    foreach ($m in $moveDisks) {
        Write-Host (" - VM {0}, disk {1}: MOVE '{2}' -> '{3}'" -f $m.VMName, $m.Letter, $m.Source, $m.Destination) -ForegroundColor Yellow
    }
    $answer = Read-Host "Type MOVE to continue with moving source VHDX file(s), or anything else to cancel"
    if ($answer -ne 'MOVE') {
        Write-Host "Cancelled by user. No VM changes were performed." -ForegroundColor Yellow
        Stop-TranscriptSafe -KeepTranscript:$ExternalTranscript
        return
    }
}

foreach ($item in $parsedItems) {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor DarkCyan
    Write-Host "Starting VM creation: $($item.BaseVMName)" -ForegroundColor Cyan
    Write-Host "Target display VM name: $($item.TargetDisplayVMName)"
    Write-Host "Configured host in file : $($item.HyperVHost)"
    Write-Host "Actual create host      : $effectiveHost"
    Write-Host "==================================================" -ForegroundColor DarkCyan

    if ($isLocal) {
        New-HVVMFromTemplate -Item $item -AllowDuplicateBaseVMName:$AllowDuplicateBaseVMName
    }
    else {
        Invoke-Command -Session $session -ErrorAction Stop -ArgumentList @($remoteCreateDefinitions,$item,[bool]$AllowDuplicateBaseVMName) -ScriptBlock {
            param([string]$createCode,[object]$vm,[bool]$allow)
            if ($null -eq $vm -or [string]::IsNullOrWhiteSpace([string]$vm.BaseVMName) -or
                [string]::IsNullOrWhiteSpace([string]$vm.TargetDisplayVMName)) {
                throw 'Remote Create received an invalid VM definition. No VM creation attempted.'
            }
            . ([scriptblock]::Create($createCode))
            if (-not (Get-Command New-HVVMFromTemplate -CommandType Function -ErrorAction SilentlyContinue)) {
                throw 'Remote Create function was not loaded. No VM creation attempted.'
            }
            New-HVVMFromTemplate -Item $vm -AllowDuplicateBaseVMName:$allow
        }
    }
    if ($item.Clustered) {
        if (-not $clusterName) { throw "Cannot register VM '$($item.TargetDisplayVMName)': cluster not resolved." }
        Write-Host "Registering cluster role for '$($item.TargetDisplayVMName)' in '$clusterName'..." -ForegroundColor Cyan
        # Cluster cmdlets run on the jump host, not inside a WinRM session.
        # Avoid double-hop/delegation failures on the selected Hyper-V node.
        $registeredRole = Get-HVClusterVMRole -VMName $item.TargetDisplayVMName -ClusterName $clusterName
        if ($registeredRole) {
            Write-Host "Cluster role already exists for '$($item.TargetDisplayVMName)' in '$clusterName'; skipping registration." -ForegroundColor Yellow
        }
        else {
            Add-HVClusterVMRole -VMName $item.TargetDisplayVMName -ClusterName $clusterName
            $registeredRole = Get-HVClusterVMRole -VMName $item.TargetDisplayVMName -ClusterName $clusterName
            if (-not $registeredRole) { throw "Cluster role for '$($item.TargetDisplayVMName)' was not found after registration in '$clusterName'." }
        }
        Write-Host "Cluster role registered: $($item.TargetDisplayVMName)" -ForegroundColor Green
    }
    if (@($item.CreateTags).Count -gt 0) {
        # This is a newly created VM. Do not query or merge existing tags.
        # Locate the exact new VM by its full display name on the creation host,
        # then use its immutable ID for the verified Notes write.
        $CreatedVM = Invoke-Command -ComputerName $effectiveHost -ErrorAction Stop -ScriptBlock {
            param([string]$ExpectedName)
            $matches = @(Get-VM -Name $ExpectedName -ErrorAction Stop | Where-Object { $_.Name -ceq $ExpectedName })
            if ($matches.Count -ne 1) { throw "Expected one newly created VM '$ExpectedName', found $($matches.Count)." }
            [pscustomobject]@{ Id = [string]$matches[0].Id; Name = [string]$matches[0].Name; Notes = [string]$matches[0].Notes }
        } -ArgumentList $item.TargetDisplayVMName
        $UpdatedNotes = Set-TagsInNotes -Notes $CreatedVM.Notes -NewTags @($item.CreateTags)
        Set-HVTagsForVMId -VMId $CreatedVM.Id -ExpectedName $CreatedVM.Name -HyperVHost $effectiveHost -NewNotes $UpdatedNotes
        Write-Host "Tags assigned and verified: $($item.TargetDisplayVMName)" -ForegroundColor Green
    }
}

Write-Host ""
Write-HVMessage -Message "All requested VM creation tasks completed successfully." -ForegroundColor Green

if ($session) { Remove-PSSession $session }
if (-not $ExternalTranscript) {
    try { Stop-Transcript | Out-Null }
    catch { }
}

}
