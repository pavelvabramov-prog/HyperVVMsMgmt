# Purpose: Get-HVInventoryClusterVMMap - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Retrieves hVInventory Cluster VMMap for the calling workflow.
function Get-HVInventoryClusterVMMap {

    param (
        [Parameter(Mandatory)]
        [string]$ClusterName
    )


    $Map = @{}

    $RolesFound  = 0
    $RolesMapped = 0


    try {

        $VMGroups = @(
            Get-ClusterGroup `
                -Cluster $ClusterName `
                -ErrorAction Stop |
            Where-Object {
                $_.GroupType -eq 'VirtualMachine'
            }
        )


        $RolesFound = $VMGroups.Count


        foreach ($Group in $VMGroups) {

            try {

                $Resources = @(
                    $Group |
                    Get-ClusterResource `
                        -ErrorAction Stop
                )


                $VMId = $null


                foreach ($Resource in $Resources) {

                    $VMId = Get-HVClusterResourceVMId -Resource $Resource -IgnoreParameterErrors
                    if (-not [string]::IsNullOrWhiteSpace([string]$VMId)) { break }


                }


                if (
                    -not [string]::IsNullOrWhiteSpace(
                        $VMId
                    )
                ) {

                    $VMId =
                        $VMId.
                            Trim().
                            Trim('{}').
                            ToLowerInvariant()


                    $Map[$VMId] =
                        [pscustomobject]@{

                            ClusterRoleName =
                                $Group.Name

                            OwnerNode =
                                [string]$Group.OwnerNode

                            ClusterState =
                                [string]$Group.State
                        }


                    $RolesMapped++
                }
                else {

                    Write-Warning (
                        "Cluster role '{0}' did not expose a VmId." -f
                        $Group.Name
                    )
                }
            }
            catch {

                Write-Warning (
                    "Unable to map cluster role '{0}': {1}" -f
                    $Group.Name,
                    $_.Exception.Message
                )
            }
        }
    }
    catch {

        Write-Warning (
            "Unable to build VM map for cluster '{0}': {1}" -f
            $ClusterName,
            $_.Exception.Message
        )
    }


    [pscustomobject]@{

        Map         = $Map
        RolesFound  = $RolesFound
        RolesMapped = $RolesMapped
    }
}


