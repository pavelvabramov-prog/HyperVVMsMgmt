# Purpose: Get-ClusterVMInfo - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Retrieves cluster VMInfo for the calling workflow.
function Get-ClusterVMInfo {
    param(
        [Parameter(Mandatory = $true)]
        $VM
    )

    $result = [ordered]@{
        ClusterModuleAvailable = $false
        IsClustered            = $false
        ClusterGroup           = $null
        ClusterResources       = @()
        MatchMethod            = $null
        MatchedResource        = $null
        MatchedParameter       = $null
        Errors                 = @()
    }

    $clusterModule = Get-Module -ListAvailable -Name FailoverClusters
    if (-not $clusterModule) {
        return [pscustomobject]$result
    }

    $result.ClusterModuleAvailable = $true

    try {
        Import-Module FailoverClusters -ErrorAction Stop | Out-Null

        $group = $null
        $matchedResource = $null
        $matchedParameter = $null

        # v1.9+: preferred cluster match is by VM Id, not by name.
        # This is reliable when the VM display name, cluster group name, and cluster resource name differ.
        $vmIdText = $null
        if ($VM.Id) {
            $vmIdText = $VM.Id.ToString()
        }

        if (-not [string]::IsNullOrWhiteSpace($vmIdText)) {
            try {
                $vmResources = @(Get-ClusterResource -ErrorAction Stop | Where-Object { $_.ResourceType -eq 'Virtual Machine' })

                foreach ($res in $vmResources) {
                    $params = @()
                    try {
                        $params = @(Get-ClusterParameter -InputObject $res -ErrorAction Stop)
                    }
                    catch {
                        continue
                    }

                    $hit = $params | Where-Object {
                        $null -ne $_.Value -and ($_.Value.ToString() -match [regex]::Escape($vmIdText))
                    } | Select-Object -First 1

                    if ($hit) {
                        $matchedResource = $res
                        $matchedParameter = $hit.Name
                        break
                    }
                }

                if ($matchedResource) {
                    $ownerGroupName = $matchedResource.OwnerGroup.ToString()
                    try {
                        $group = Get-ClusterGroup -Name $ownerGroupName -ErrorAction Stop
                    }
                    catch {
                        $group = $null
                        $result.Errors += "Matched VM Id in cluster resource '$($matchedResource.Name)', but could not read owner group '$ownerGroupName': $($_.Exception.Message)"
                    }

                    if ($group) {
                        $result.MatchMethod      = "VMId"
                        $result.MatchedResource  = $matchedResource.Name
                        $result.MatchedParameter = $matchedParameter
                    }
                }
            }
            catch {
                $result.Errors += "VM Id based cluster lookup failed: $($_.Exception.Message)"
            }
        }

        # Fallback 1: exact group name.
        if (-not $group) {
            try {
                $group = Get-ClusterGroup -Name $VM.Name -ErrorAction Stop
                $result.MatchMethod = "ExactGroupName"
            }
            catch {
                $group = $null
            }
        }

        # Fallback 2: SafeBoundary group name. This scans group names only, not all resources/parameters.
        if (-not $group) {
            try {
                $groupMatches = @(Get-ClusterGroup -ErrorAction Stop | Where-Object {
                    Test-SafeBoundaryMatch -BaseName $VM.Name -CandidateName $_.Name
                })

                if ($groupMatches.Count -eq 1) {
                    $group = $groupMatches[0]
                    $result.MatchMethod = "SafeBoundaryGroupName"
                }
                elseif ($groupMatches.Count -gt 1) {
                    $result.Errors += "More than one cluster group matched VM name '$($VM.Name)' by SafeBoundary: $(( $groupMatches | Select-Object -ExpandProperty Name ) -join ', ')"
                }
            }
            catch {
                $result.Errors += "SafeBoundary cluster-group lookup failed: $($_.Exception.Message)"
            }
        }

        # Fallback 3: SafeBoundary resource name among Virtual Machine resources only.
        if (-not $group) {
            try {
                $resourceMatches = @(Get-ClusterResource -ErrorAction Stop | Where-Object {
                    $_.ResourceType -eq 'Virtual Machine' -and
                    (Test-SafeBoundaryMatch -BaseName $VM.Name -CandidateName $_.Name)
                })

                if ($resourceMatches.Count -eq 1) {
                    $matchedResource = $resourceMatches[0]
                    $ownerGroupName = $matchedResource.OwnerGroup.ToString()
                    $group = Get-ClusterGroup -Name $ownerGroupName -ErrorAction Stop
                    $result.MatchMethod     = "SafeBoundaryResourceName"
                    $result.MatchedResource = $matchedResource.Name
                }
                elseif ($resourceMatches.Count -gt 1) {
                    $result.Errors += "More than one cluster VM resource matched VM name '$($VM.Name)' by SafeBoundary: $(( $resourceMatches | Select-Object -ExpandProperty Name ) -join ', ')"
                }
            }
            catch {
                $result.Errors += "SafeBoundary cluster-resource lookup failed: $($_.Exception.Message)"
            }
        }

        if (-not $group) {
            if ($VM.PSObject.Properties.Name -contains 'IsClustered' -and $VM.IsClustered) {
                $result.Errors += "VM reports IsClustered = True, but no matching cluster role was found by VM Id, exact group name, SafeBoundary group name, or SafeBoundary resource name."
            }
            return [pscustomobject]$result
        }

        $result.IsClustered  = $true
        $result.ClusterGroup = $group

        try {
            $result.ClusterResources = @(Get-ClusterResource -ErrorAction Stop | Where-Object { $_.OwnerGroup -eq $group.Name })
        }
        catch {
            $result.Errors += "Unable to enumerate cluster resources for group '$($group.Name)': $($_.Exception.Message)"
        }
    }
    catch {
        $result.Errors += $_.Exception.Message
    }

    return [pscustomobject]$result
}
