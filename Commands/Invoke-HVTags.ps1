# Purpose: Invoke-HVTags - command entry point.
# Maintains the existing validation, logging, and execution behavior.

# Tags command: validates and reads or updates Tags stored in VM Notes.
function Invoke-HVTags {
    [CmdletBinding()]
    param(
        [string]$ComputerName,
        [ValidateSet('HyperV','PhysicalWindows','PhysicalLinux')][string]$Type,
        [string]$HyperVHost,
        [string]$UserName,
        [switch]$Get,
        [switch]$Add,
        [switch]$Set,
        [switch]$ReplaceAll,
        [switch]$Remove,
        [switch]$Clear,
        [string[]]$Tags,
        [string]$ServerListFile,
        [switch]$AllowCustomTags,
        [switch]$ValidateOnly,
        [switch]$ListTags,
        [switch]$Help,
        [switch]$ConsoleRelaunched
    )
    $catalogPath = Join-Path $PSScriptRoot '..\Config\ServerTags.config.txt'
    if ($Help) {
        Write-Host @'
hv-tags -Get|-Add|-Set|-ReplaceAll|-Remove|-Clear -ComputerName NAME -Type HyperV|PhysicalWindows|PhysicalLinux
        [-HyperVHost HOST_OR_CLUSTER] [-UserName SSH_USER] [-Tags CATEGORY:VALUE,...]
        [-AllowCustomTags] [-ValidateOnly]
hv-tags -ServerListFile PATH -Get|-Add|-Set|-ReplaceAll|-Remove|-Clear [-AllowCustomTags] [-ValidateOnly]
hv-tags -ListTags

Get         Read tags; -Tags not permitted.
Add         Add specified tags; preserve existing tags.
Set         Set or replace all values in the specified categories; preserve other categories.
ReplaceAll  Remove ALL existing tags and replace with supplied tags.
Remove      Remove specified CATEGORY:VALUE tags only.
Clear       Remove all tags; -Tags not permitted.

-Add, -Set, -ReplaceAll and -Remove require -Tags for single-target mode.
For bulk CSV, tag values come from category columns, not -Tags.
-Add, -Set, -ReplaceAll and -Remove require nonempty tags in every CSV row.
-ValidateOnly previews changes without writing; -Get is already read-only.

Bulk CSV columns: ServerName,TargetHost,Scope,Env,App,Role,Contact
TargetHost is a Hyper-V host/cluster or PhysicalWindows/PhysicalLinux.
Multiple values in a category cell are separated by semicolons. Empty cells are ignored.
For PhysicalLinux bulk operations supply -UserName.
Catalog: Config\ServerTags.config.txt. ALLOW_CUSTOM=YES permits any nonempty value in that category.
Unknown categories require -AllowCustomTags. Existing legacy/custom tags are not automatically renamed.
Ambiguous VM matches require interactive selection; Q skips that server.
CSV preflight validates every row before any server is processed.
'@
        return
    }
    $catalog = Read-HVTagCatalog -Path $catalogPath
    if ($ListTags) {
        foreach ($key in @('SCOPE','ENV','APP','ROLE','CONTACT') + @($catalog.Keys | Where-Object { $_ -notin @('SCOPE','ENV','APP','ROLE','CONTACT') } | Sort-Object)) {
            $values = @($catalog[$key].Values.Values | Sort-Object)
            if ($catalog[$key].AllowCustom) { $values += '(any value permitted)' }
            Write-Host "$(@{SCOPE='Scope';ENV='Env';APP='App';ROLE='Role';CONTACT='Contact'}[$key]) : $($values -join ', ')"
        }
        return
    }
    $chosen = @()
    foreach ($candidate in @('Get','Add','Set','ReplaceAll','Remove','Clear')) { if (Get-Variable -Name $candidate -ValueOnly) { $chosen += $candidate } }
    if ($chosen.Count -ne 1) { throw 'Specify exactly one action switch: -Get, -Add, -Set, -ReplaceAll, -Remove, or -Clear.' }
    $Action = $chosen[0]
    if ($Action -eq 'Get' -and $ValidateOnly) { throw 'Get is already read-only; do not use -ValidateOnly.' }
    if ($ServerListFile) {
        if ($ComputerName -or $Type -or $HyperVHost -or $Tags) { throw '-ServerListFile cannot be combined with single-target parameters.' }
        try {
            $entries = @(Read-HVTagServerList -Path $ServerListFile -Catalog $catalog -AllowCustomTags:$AllowCustomTags -Action $Action)
        } catch {
            Write-Warning "CSV preflight failed (no servers processed): $($_.Exception.Message)"
            return [pscustomobject]@{ Status='Failed'; Changed=$false; Detail=$_.Exception.Message }
        }
        $counts = @{ Success=0; Failed=0; Skipped=0 }
        foreach ($entry in $entries) {
            $targetType = 'HyperV'
            $hostName = $entry.TargetHost
            if ($hostName -in @('PhysicalWindows','PhysicalLinux')) { $targetType = $hostName; $hostName = $null }
            Write-Host "Processing $($entry.ServerName) on $($entry.TargetHost)..."
            try {
                $result = Invoke-HVTagSingle -ComputerName $entry.ServerName -Type $targetType -HyperVHost $hostName -UserName $UserName -Action $Action -Tags $entry.Tags -ValidateOnly:$ValidateOnly
                $entryStatus = if ($result.Status -in @('Success','Skipped','Failed')) { $result.Status } else { 'Failed' }
                $detail = if ($result.Detail) { [string]$result.Detail } elseif ($result.Reason) { [string]$result.Reason } else { '' }
                $display = [pscustomobject]@{
                    ServerName=$entry.ServerName; TargetHost=$entry.TargetHost
                    VMName=$result.VMName; Action=$Action; PreviousTags=$result.PreviousTags
                    Tags=$result.Tags; Changed=$result.Changed; ValidateOnly=[bool]$ValidateOnly
                    Status=$entryStatus; Detail=$detail
                }
            } catch {
                $entryStatus = 'Failed'
                $display = [pscustomobject]@{ ServerName=$entry.ServerName; TargetHost=$entry.TargetHost; Status='Failed'; Detail=$_.Exception.Message }
            }
            $counts[$entryStatus]++
            Write-Host (($display | Format-List | Out-String).TrimEnd())
            Write-Host ''
        }
        Write-Host "Bulk summary: $($counts.Success) succeeded; $($counts.Failed) failed; $($counts.Skipped) skipped."
        return
    }
    if (-not $ComputerName -or -not $Type) { throw 'Single-target mode requires -ComputerName and -Type.' }
    $normalized = @()
    if ($Action -in @('Add','Set','ReplaceAll','Remove')) {
        if (-not $Tags) { throw "-Tags is required for -$Action." }
        try {
            $normalized = @(Test-ApprovedTags -InputTags $Tags -Catalog $catalog -AllowCustomTags:$AllowCustomTags -AllowLegacyForRemoval:($Action -eq 'Remove'))
        } catch {
            $message = $_.Exception.Message
            Write-Warning "Tag validation failed: $message. No changes were made."
            return [pscustomobject]@{
                ComputerName = $ComputerName
                Type = $Type
                Action = $Action
                Tags = ($Tags -join '; ')
                Changed = $false
                ValidateOnly = [bool]$ValidateOnly
                Status = 'Failed'
                Detail = $message
            }
        }
        if ($normalized.Count -eq 0) { throw "-Tags contains no values for -$Action." }
    } elseif ($Tags) { throw "-Tags is not valid with -Action $Action." }
    Invoke-HVTagSingle -ComputerName $ComputerName -Type $Type -HyperVHost $HyperVHost -UserName $UserName -Action $Action -Tags $normalized -ValidateOnly:$ValidateOnly
}
