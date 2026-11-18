# Purpose: Get-HyperVVMInventory - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Retrieves hyper VVMInventory for the calling workflow.
function Get-HyperVVMInventory {

    param (
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [string]$ClusterName,

        [hashtable]$ClusterVMMap
    )


    $sharedRoot = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Shared'
    $tagReaderSource = (Get-Content -LiteralPath (Join-Path $sharedRoot 'ConvertTo-HVNormalizedTags.ps1') -Raw -ErrorAction Stop) + "`n" + (Get-Content -LiteralPath (Join-Path $sharedRoot 'Get-HVTagsFromNotes.ps1') -Raw -ErrorAction Stop)
    Invoke-Command `
        -ComputerName $ComputerName `
        -ArgumentList $ClusterName,$ClusterVMMap,$tagReaderSource `
        -ErrorAction Stop `
        -ScriptBlock {

        param (
            $ClusterName,
            $ClusterVMMap,
            [string]$TagReaderSource
        )
        . ([scriptblock]::Create($TagReaderSource))


        Import-Module Hyper-V -ErrorAction Stop


        # ====================================================
        # HELPERS
        # ====================================================

        # Converts tB for the calling workflow.
        function ConvertTo-TB {

            param (
                [double]$Bytes
            )


            if (-not $Bytes) {
                return 0
            }


            return [math]::Round(
                ($Bytes / 1TB),
                3
            )
        }


        # Retrieves normalized Volume for the calling workflow.
        function Get-NormalizedVolume {

            param (
                [string]$Path
            )


            if ([string]::IsNullOrWhiteSpace($Path)) {
                return $null
            }


            # Standard CSV
            if (
                $Path -match
                '(?i)\\ClusterStorage\\Volume(\d+)'
            ) {

                return "Volume$($Matches[1])"
            }


            # Named CSV
            if (
                $Path -match
                '(?i)\\ClusterStorage\\([^\\]+)'
            ) {

                return $Matches[1]
            }


            # Drive letter
            if ($Path -match '^([A-Za-z]):') {

                return "$($Matches[1].ToUpper()):"
            }


            # UNC share
            if (
                $Path -match
                '^(\\\\[^\\]+\\[^\\]+)'
            ) {

                return $Matches[1]
            }


            return $Path
        }


        # ====================================================
        # GET REGISTERED VMs
        # ====================================================

        $VMs = @(
            Get-VM -ErrorAction Stop
        )


        foreach ($VM in $VMs) {


            # =================================================
            # VM ID
            # =================================================

            $VMId =
                $VM.Id.
                    ToString().
                    Trim('{}').
                    ToLowerInvariant()


            # =================================================
            # CLUSTER ROLE CORRELATION
            # =================================================

            $ClusterRoleName = $null
            $IsClustered     = "No"


            if (
                $ClusterVMMap -and
                $ClusterVMMap.ContainsKey($VMId)
            ) {

                $ClusterRoleName =
                    $ClusterVMMap[$VMId].
                        ClusterRoleName

                $IsClustered =
                    "Yes"
            }


            # =================================================
            # VM FULL NAME
            # =================================================

            if (
                -not [string]::IsNullOrWhiteSpace(
                    $ClusterRoleName
                )
            ) {

                $VMFullName =
                    $ClusterRoleName
            }
            else {

                $VMFullName =
                    $VM.Name
            }


                        # =================================================
            # SHORT VM NAME
            # =================================================

            $VMName = $null


            # -------------------------------------------------
            # First look for conventional computer names.
            #
            # Examples:
            #   HVTSTWS133
            #   ALNDELX003
            #   HVTSTLX024
            # -------------------------------------------------

            $Tokens = @(
                $VMFullName -split '[\s\-]+'
            )


            foreach ($Token in $Tokens) {

                if (
                    $Token -match
                    '^(?i)[A-Z]{3,}[A-Z0-9]*\d{2,}$'
                ) {

                    $VMName =
                        $Token.ToUpperInvariant()

                    break
                }
            }


            # -------------------------------------------------
            # If no conventional computer name was found,
            # handle descriptive VM names containing underscores.
            #
            # Example:
            #
            #   SHUTDOWN - TST_Connector_02 - 2025-05-03
            #
            # becomes:
            #
            #   TST_Connector_02
            # -------------------------------------------------

            if (-not $VMName) {

                $NameParts = @(
                    $VMFullName -split '\s+-\s+'
                )


                foreach ($Part in $NameParts) {

                    $Candidate =
                        $Part.Trim()


                    if (
                        $Candidate -match '_' -and
                        $Candidate -match '\d'
                    ) {

                        $VMName =
                            $Candidate

                        break
                    }
                }
            }


            # -------------------------------------------------
            # Try the registered Hyper-V name as well.
            # -------------------------------------------------

            if (-not $VMName) {

                $HyperVTokens = @(
                    $VM.Name -split '[\s\-]+'
                )


                foreach ($Token in $HyperVTokens) {

                    if (
                        $Token -match
                        '^(?i)[A-Z]{3,}[A-Z0-9]*\d{2,}$'
                    ) {

                        $VMName =
                            $Token.ToUpperInvariant()

                        break
                    }
                }
            }


            # -------------------------------------------------
            # Final fallback
            # -------------------------------------------------

            if (-not $VMName) {

                $VMName =
                    ($VM.Name -split '\s+')[0]
            }


            # =================================================
            # VM STATE
            # =================================================

            $VMState =
                [string]$VM.State


            # =================================================
            # CPU COMPATIBILITY
            # =================================================

            # =================================================
            # CPU COMPATIBILITY
            # =================================================

            try {

                $Processor =
                    Get-VMProcessor `
                        -VM $VM `
                        -ErrorAction Stop


                if (
                    $Processor.
                        CompatibilityForMigrationEnabled
                ) {

                    $CPUCompatibility = "Set"
                }
                else {

                    $CPUCompatibility = "Not Set"
                }
            }
            catch {

                $CPUCompatibility = "Unknown"
            }


            # =================================================
            # NETWORKS
            # =================================================

            try {

                $Networks = @(
                    Get-VMNetworkAdapter `
                        -VM $VM `
                        -ErrorAction Stop |
                    Where-Object {
                        -not [string]::IsNullOrWhiteSpace(
                            $_.SwitchName
                        )
                    } |
                    Select-Object `
                        -ExpandProperty SwitchName `
                        -Unique
                )


                if ($Networks.Count -gt 0) {

                    $VMNetwork =
                        $Networks -join "; "
                }
                else {

                    $VMNetwork =
                        "Disconnected"
                }
            }
            catch {

                $VMNetwork =
                    "Unknown"
            }


            # =================================================
            # VM HARD DISKS
            # =================================================

            try {

                $VMDisks = @(
                    Get-VMHardDiskDrive `
                        -VM $VM `
                        -ErrorAction Stop
                )
            }
            catch {

                $VMDisks = @()
            }


            # =================================================
            # REQUIRED VHD CHAIN
            # =================================================

            $VHDChainFiles = @{}


            foreach ($Disk in $VMDisks) {

                if (
                    [string]::IsNullOrWhiteSpace(
                        $Disk.Path
                    )
                ) {

                    continue
                }


                $CurrentPath =
                    $Disk.Path


                while (
                    -not [string]::IsNullOrWhiteSpace(
                        $CurrentPath
                    )
                ) {

                    try {

                        $VHDInfo =
                            Get-VHD `
                                -Path $CurrentPath `
                                -ErrorAction Stop


                        $NormalizedPath =
                            $VHDInfo.Path.
                                ToLowerInvariant()


                        $Extension =
                            [IO.Path]::
                                GetExtension(
                                    $VHDInfo.Path
                                ).
                                ToLowerInvariant()


                        if (
                            $Extension -eq '.avhd' -or
                            $Extension -eq '.avhdx'
                        ) {

                            $DiskType =
                                "Checkpoint"
                        }
                        else {

                            $DiskType =
                                "Base"
                        }


                        if (
                            -not $VHDChainFiles.
                                ContainsKey(
                                    $NormalizedPath
                                )
                        ) {

                            $VHDChainFiles[
                                $NormalizedPath
                            ] =
                                [pscustomobject]@{

                                    Path =
                                        $VHDInfo.Path

                                    FileSize =
                                        [double]$VHDInfo.FileSize

                                    Type =
                                        $DiskType
                                }
                        }


                        if (
                            [string]::IsNullOrWhiteSpace(
                                $VHDInfo.ParentPath
                            )
                        ) {

                            break
                        }


                        $CurrentPath =
                            $VHDInfo.ParentPath
                    }
                    catch {

                        break
                    }
                }
            }


            # =================================================
            # ACTUAL VHD STORAGE
            # =================================================

            [double]$ActualBytes = 0


            foreach (
                $VHDFile in
                $VHDChainFiles.Values
            ) {

                $ActualBytes +=
                    $VHDFile.FileSize
            }


            $VMActualSizeTB =
                ConvertTo-TB $ActualBytes


            # =================================================
            # CHECKPOINT SIZE
            # =================================================

            [double]$CheckpointBytes = 0


            foreach (
                $VHDFile in
                $VHDChainFiles.Values
            ) {

                if (
                    $VHDFile.Type -eq
                    "Checkpoint"
                ) {

                    $CheckpointBytes +=
                        $VHDFile.FileSize
                }
            }


            $CheckpointSizeTB =
                ConvertTo-TB $CheckpointBytes


            # =================================================
            # CHECKPOINT PRESENCE
            # =================================================

            try {

                $Snapshots = @(
                    Get-VMSnapshot `
                        -VM $VM `
                        -ErrorAction Stop
                )


                if ($Snapshots.Count -gt 0) {

                    $HasCheckpoints =
                        "Yes"
                }
                else {

                    $HasCheckpoints =
                        "No"
                }
            }
            catch {

                if ($CheckpointBytes -gt 0) {

                    $HasCheckpoints =
                        "Yes"
                }
                else {

                    $HasCheckpoints =
                        "Unknown"
                }
            }


            # =================================================
            # PROVISIONED SIZE
            # =================================================

            [double]$ProvisionedBytes = 0


            foreach ($Disk in $VMDisks) {

                if (
                    [string]::IsNullOrWhiteSpace(
                        $Disk.Path
                    )
                ) {

                    continue
                }


                try {

                    $AttachedVHD =
                        Get-VHD `
                            -Path $Disk.Path `
                            -ErrorAction Stop


                    $ProvisionedBytes +=
                        [double]$AttachedVHD.Size
                }
                catch {
                }
            }


            $VMProvisionedTB =
                ConvertTo-TB $ProvisionedBytes


            # =================================================
            # PASS-THROUGH LUNS
            # =================================================
            #
            # A pass-through LUN is a host-visible physical disk
            # attached directly to the VM through Hyper-V.
            #
            # This is NOT the same as Virtual Fibre Channel.
            #
            # =================================================

            $PassThroughDisks = @(
                $VMDisks |
                Where-Object {

                    [string]::IsNullOrWhiteSpace(
                        $_.Path
                    ) -and
                    (
                        $null -ne $_.DiskNumber -or
                        $null -ne $_.DiskIdentifier
                    )
                }
            )


            if ($PassThroughDisks.Count -gt 0) {

                $PassThroughLUNs =
                    "Yes"
            }
            else {

                $PassThroughLUNs =
                    "No"
            }


            # =================================================
            # PASS-THROUGH SIZE
            # =================================================

            [double]$PassThroughBytes = 0


            foreach (
                $PassThroughDisk in
                $PassThroughDisks
            ) {

                try {

                    if (
                        $null -ne
                        $PassThroughDisk.DiskNumber
                    ) {

                        $PhysicalDisk =
                            Get-Disk `
                                -Number $PassThroughDisk.DiskNumber `
                                -ErrorAction Stop


                        $PassThroughBytes +=
                            [double]$PhysicalDisk.Size
                    }
                }
                catch {
                }
            }


            $PassThroughSizeTB =
                ConvertTo-TB $PassThroughBytes


            # =================================================
            # VIRTUAL FIBRE CHANNEL
            # =================================================
            #
            # Host-side only.
            #
            # No query is made to the guest OS.
            #
            # Works for:
            #   Windows guests
            #   Linux guests
            #   powered-off VMs
            #
            # =================================================

            try {

                $VirtualFCAdapters = @(
                    Get-VMFibreChannelHba `
                        -VMName $VM.Name `
                        -ErrorAction Stop
                )
            }
            catch {

                $VirtualFCAdapters = @()
            }


            if ($VirtualFCAdapters.Count -gt 0) {

                $VirtualFC =
                    "Yes ($($VirtualFCAdapters.Count))"


                $VirtualSANs = @(
                    $VirtualFCAdapters |
                    ForEach-Object {
                        $_.SanName
                    } |
                    Where-Object {
                        -not [string]::IsNullOrWhiteSpace(
                            $_
                        )
                    } |
                    Sort-Object -Unique
                )


                if ($VirtualSANs.Count -gt 0) {

                    $VirtualSAN =
                        $VirtualSANs -join "; "
                }
                else {

                    $VirtualSAN =
                        "Unknown"
                }
            }
            else {

                $VirtualFC =
                    "No"

                $VirtualSAN =
                    ""
            }


            # =================================================
            # VOLUMES
            # =================================================

            $Volumes = @()


            foreach (
                $VHDFile in
                $VHDChainFiles.Values
            ) {

                $Volume =
                    Get-NormalizedVolume `
                        -Path $VHDFile.Path


                if ($Volume) {

                    $Volumes +=
                        $Volume
                }
            }


            if (
                -not [string]::IsNullOrWhiteSpace(
                    $VM.ConfigurationLocation
                )
            ) {

                $Volume =
                    Get-NormalizedVolume `
                        -Path $VM.ConfigurationLocation


                if ($Volume) {

                    $Volumes +=
                        $Volume
                }
            }


            if (
                -not [string]::IsNullOrWhiteSpace(
                    $VM.SnapshotFileLocation
                )
            ) {

                $Volume =
                    Get-NormalizedVolume `
                        -Path $VM.SnapshotFileLocation


                if ($Volume) {

                    $Volumes +=
                        $Volume
                }
            }


            $Volumes = @(
                $Volumes |
                Sort-Object -Unique
            )


            if ($Volumes.Count -gt 0) {

                $VolumeList =
                    $Volumes -join "; "
            }
            else {

                $VolumeList =
                    "Unknown"
            }


            # Shared Hyper-V Notes parser (loaded into this remote session).
            $InventoryTagValues = @{}
            foreach ($Category in @('Scope','Env','App','Role','Contact')) {
                $InventoryTagValues[$Category] = [System.Collections.Generic.List[string]]::new()
            }
            foreach ($TagEntry in @(Get-TagsFromNotes -Notes ([string]$VM.Notes))) {
                if ($TagEntry -match '^([^:]+):(.+)$') {
                    $TagCategory = $Matches[1].Trim()
                    $TagValue = $Matches[2].Trim()
                    if ($InventoryTagValues.ContainsKey($TagCategory) -and $TagValue -and
                        -not $InventoryTagValues[$TagCategory].Contains($TagValue)) {
                        [void]$InventoryTagValues[$TagCategory].Add($TagValue)
                    }
                }
            }

            # =================================================
            # OUTPUT
            # =================================================

            [pscustomobject]@{

                'CLUSTER NAME' =
                    $ClusterName

                'HV-Host' =
                    $env:COMPUTERNAME

                'VMName' =
                    $VMName

                'VM Full Name' =
                    $VMFullName

                'State' =
                    $VMState

                'Is Clustered' =
                    $IsClustered

                'Volume(s)' =
                    $VolumeList

                'VM Actual Size, TB' =
                    $VMActualSizeTB

                'VM Provisioned Size, TB' =
                    $VMProvisionedTB

                'VMNetwork' =
                    $VMNetwork

                'CPU Compatibility' =
                    $CPUCompatibility

                'Pass-through LUNs' =
                    $PassThroughLUNs

                'Pass-through Size, TB' =
                    $PassThroughSizeTB

                'Virtual FC' =
                    $VirtualFC

                'Virtual SAN' =
                    $VirtualSAN

                'Checkpoints' =
                    $HasCheckpoints

                'CheckpointSize, TB' =
                    $CheckpointSizeTB

                'Scope' = ($InventoryTagValues['Scope'] -join '; ')
                'Env' = ($InventoryTagValues['Env'] -join '; ')
                'App' = ($InventoryTagValues['App'] -join '; ')
                'Role' = ($InventoryTagValues['Role'] -join '; ')
                'Contact' = ($InventoryTagValues['Contact'] -join '; ')

                'Status' =
                    "OK"
            }
        }
    }
}


