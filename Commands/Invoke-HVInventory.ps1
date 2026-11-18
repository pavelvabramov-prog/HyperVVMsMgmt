# Purpose: Invoke-HVInventory - command entry point.
# Maintains the existing validation, logging, and execution behavior.

# Inventory command: collects VM and cluster information for the selected report profile.
function Invoke-HVInventory {
    [CmdletBinding()]
    param(
        [string[]]$ServerList,
        [string]$ReportFile = 'C:\Temp\HyperV_VM_Migration_Inventory.csv',
        [string]$ReportProfile = 'Default',
        [switch]$Help
    )
    if ($Help) { Get-Help Invoke-HVInventory -Detailed; return }
    if (-not $ServerList) { Write-Error '-ServerList is required. Example: hv-inventory -ServerList HVTSTCLUSTER6'; return }
    # Validate profile configuration before contacting Hyper-V hosts.
    $ProfileConfigPath = Join-Path $PSScriptRoot '..\Config\HyperVInventory.config.txt'
    $ProfileConfig = Read-HVInventoryReportProfiles -Path $ProfileConfigPath
    if (-not $ProfileConfig.Profiles.ContainsKey($ReportProfile)) {
        throw ("Unknown inventory report profile '{0}'. Available profiles: {1}" -f $ReportProfile, (($ProfileConfig.Profiles.Keys | Sort-Object) -join ', '))
    }
    $ReportColumns = @($ProfileConfig.Profiles[$ReportProfile].ToArray())
    # Internal v1.5 property names remain unchanged; only the output header is mapped.
    $SourceColumns = @($ReportColumns | ForEach-Object { if ($_ -eq 'Cluster Name') { 'CLUSTER NAME' } else { $_ } })
    Import-Module FailoverClusters -ErrorAction SilentlyContinue
    # ============================================================
    # BUILD TARGET HOST LIST
    # ============================================================

    $HostTargets = @()


    foreach ($Target in $ServerList) {

        Write-Host ""
        Write-Host "============================================================" `
            -ForegroundColor Cyan

        Write-Host "Processing target: $Target" `
            -ForegroundColor Cyan

        Write-Host "============================================================" `
            -ForegroundColor Cyan


        if (
            Test-HVInventoryCluster `
                -Name $Target
        ) {

            Write-Host "Detected: CLUSTER" `
                -ForegroundColor Green


            try {

                $Nodes = @(
                    Get-ClusterNode `
                        -Cluster $Target `
                        -ErrorAction Stop
                )


                $ClusterMapResult =
                    Get-HVInventoryClusterVMMap `
                        -ClusterName $Target


                $ClusterVMMap =
                    $ClusterMapResult.Map


                Write-Host (
                    "Cluster VM roles found : {0}" -f
                    $ClusterMapResult.RolesFound
                ) -ForegroundColor DarkCyan


                Write-Host (
                    "Cluster VM roles mapped: {0}" -f
                    $ClusterMapResult.RolesMapped
                ) -ForegroundColor DarkCyan


                if (
                    $ClusterMapResult.RolesFound -ne
                    $ClusterMapResult.RolesMapped
                ) {

                    Write-Warning (
                        "{0} cluster VM role(s) found but only {1} " +
                        "could be mapped to VM IDs." -f
                        $ClusterMapResult.RolesFound,
                        $ClusterMapResult.RolesMapped
                    )
                }


                foreach ($Node in $Nodes) {

                    Write-Host (
                        "  Node: {0} [{1}]" -f
                        $Node.Name,
                        $Node.State
                    ) -ForegroundColor Yellow


                    $HostTargets +=
                        [pscustomobject]@{

                            Cluster =
                                $Target

                            Host =
                                $Node.Name

                            ClusterVMMap =
                                $ClusterVMMap
                        }
                }
            }
            catch {

                Write-Warning (
                    "Failed to enumerate cluster '{0}': {1}" -f
                    $Target,
                    $_.Exception.Message
                )
            }
        }
        else {

            Write-Host "Detected: HYPER-V HOST" `
                -ForegroundColor Magenta


            $HostTargets +=
                [pscustomobject]@{

                    Cluster = ""

                    Host = $Target

                    ClusterVMMap = @{}
                }
        }
    }


    # ============================================================
    # REMOVE DUPLICATE HOSTS
    # ============================================================

    $UniqueHosts = @()


    foreach ($Item in $HostTargets) {

        if (
            $UniqueHosts.Host -notcontains
            $Item.Host
        ) {

            $UniqueHosts +=
                $Item
        }
    }


    # ============================================================
    # QUERY HOSTS
    # ============================================================

    $Results = @()


    foreach ($Item in $UniqueHosts) {

        Write-Host ""
        Write-Host (
            "Querying Hyper-V host: {0}" -f
            $Item.Host
        ) -ForegroundColor Cyan


        try {

            $VMResults = @(
                Get-HyperVVMInventory `
                    -ComputerName $Item.Host `
                    -ClusterName $Item.Cluster `
                    -ClusterVMMap $Item.ClusterVMMap
            )


            if ($VMResults.Count -eq 0) {

                Write-Host "  No registered VMs found." `
                    -ForegroundColor Yellow
            }
            else {

                Write-Host (
                    "  Found {0} registered VM(s)." -f
                    $VMResults.Count
                ) -ForegroundColor Green


                $Results +=
                    $VMResults
            }
        }
        catch {

            $ErrorText =
                $_.Exception.Message


            Write-Warning (
                "Failed to query '{0}': {1}" -f
                $Item.Host,
                $ErrorText
            )


            $Results +=
                [pscustomobject]@{

                    'CLUSTER NAME' = $Item.Cluster
                    'HV-Host' = $Item.Host

                    'VMName' = ""
                    'VM Full Name' = ""

                    'State' = ""
                    'Is Clustered' = ""
                    'Volume(s)' = ""

                    'VM Actual Size, TB' = 0
                    'VM Provisioned Size, TB' = 0

                    'VMNetwork' = ""
                    'CPU Compatibility' = ""

                    'Pass-through LUNs' = ""
                    'Pass-through Size, TB' = 0

                    'Virtual FC' = ""
                    'Virtual SAN' = ""

                    'Checkpoints' = ""
                    'CheckpointSize, TB' = 0

                    'Status' =
                        "QUERY FAILED: $ErrorText"
                }
        }
    }


    # ============================================================
    # FINAL REPORT COLUMNS
    # ============================================================

    # ============================================================
    # CLEAN REMOTING PROPERTIES / SORT
    # ============================================================

    $FinalResults = @(
        $Results |
            Sort-Object 'CLUSTER NAME', 'HV-Host', 'VMName' |
            ForEach-Object {
                $record = $_
                $ordered = [ordered]@{}
                for ($i = 0; $i -lt $ReportColumns.Count; $i++) {
                    $ordered[$ReportColumns[$i]] = $record.($SourceColumns[$i])
                }
                [pscustomobject]$ordered
            }
    )

    # ============================================================
    # DISPLAY
    # ============================================================

    Write-Host ""
    Write-Host "============================================================" `
        -ForegroundColor Cyan

    Write-Host " VM MIGRATION INVENTORY v1.5" `
        -ForegroundColor Cyan

    Write-Host "============================================================" `
        -ForegroundColor Cyan


    Write-Host " Report profile: $ReportProfile" -ForegroundColor DarkCyan
    $FinalResults | Format-Table -Property $ReportColumns -AutoSize

    # ============================================================
    # EXPORT CSV
    # ============================================================

    try {

        $ReportDirectory =
            Split-Path `
                -Path $ReportFile `
                -Parent


        if (
            $ReportDirectory -and
            -not (
                Test-Path `
                    -LiteralPath $ReportDirectory
            )
        ) {

            New-Item `
                -Path $ReportDirectory `
                -ItemType Directory `
                -Force |
                Out-Null
        }


        $FinalResults |
            Export-Csv `
                -Path $ReportFile `
                -Delimiter ',' `
                -NoTypeInformation `
                -Encoding UTF8


        Write-Host ""
        Write-Host "Report saved:" `
            -ForegroundColor Green

        Write-Host "  $ReportFile"
        Write-Host ""
    }
    catch {

        Write-Warning (
            "Failed to save report: {0}" -f
            $_.Exception.Message
        )
    }
}
