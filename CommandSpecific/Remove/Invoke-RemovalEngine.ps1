# Purpose: Invoke-RemovalEngine - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Step 3: extracted remote/local execution helper. EngineCode explicitly passed across module scopes.
function Invoke-RemovalEngine {
    param([string]$Node,[string]$Name,[string]$ExpectedVMId,[string]$ExpectedVMName,[bool]$DryRun,[bool]$SkipPrimary,[bool]$ForceFolders,[bool]$RoleHandled,[bool]$ExternalAD,[string]$EngineCode,[string]$InspectionContext = 'Validation')
    $params = @($Name,$DryRun,$SkipPrimary,$ForceFolders,$RoleHandled,$ExternalAD)
    if ($Node -ieq $env:COMPUTERNAME -or $Node -ieq "$env:COMPUTERNAME.$env:USERDNSDOMAIN" -or $Node -ieq 'localhost' -or $Node -eq '.') {
        & ([scriptblock]::Create($EngineCode)) -VMName $Name -ExpectedVMId $ExpectedVMId -ExpectedVMName $ExpectedVMName -ValidateOnly:$DryRun -Y:$SkipPrimary -ForceFolderCleanup:$ForceFolders -ClusterRoleHandledExternally:$RoleHandled -ADHandledExternally:$ExternalAD -InspectionContext $InspectionContext
    } else {
        Write-Host "Connecting to Hyper-V node $Node..." -ForegroundColor Cyan
        $s = Invoke-HVTiming -Action Measure -TimingLabel 'Connect to Hyper-V node' -Target $Node -ScriptBlock { New-PSSession -ComputerName $Node -ErrorAction Stop }
        try {
            Write-Host $(if ($DryRun) { 'VM and storage inspection on remote node...' } else { 'VM and storage deletion on remote node...' }) -ForegroundColor Cyan
            Invoke-HVTiming -Action Measure -TimingLabel $(if ($DryRun) {'VM and storage inspection'} else {'VM and storage deletion'}) -Target $Node -ScriptBlock { Invoke-Command -Session $s -ScriptBlock {
                param([string]$code,[string]$vm,[string]$expectedId,[string]$expectedName,[bool]$validate,[bool]$yes,[bool]$force,[bool]$handled,[bool]$externalAD,[string]$inspectionContext)
                & ([scriptblock]::Create($code)) -VMName $vm -ExpectedVMId $expectedId -ExpectedVMName $expectedName -ValidateOnly:$validate -Y:$yes -ForceFolderCleanup:$force -ClusterRoleHandledExternally:$handled -ADHandledExternally:$externalAD -InspectionContext $inspectionContext
            } -ArgumentList $EngineCode,$Name,$ExpectedVMId,$ExpectedVMName,$DryRun,$SkipPrimary,$ForceFolders,$RoleHandled,$ExternalAD,$InspectionContext -ErrorAction Stop }
        } finally {
            Write-Host "Disconnecting from Hyper-V node $Node..." -ForegroundColor Cyan
            Invoke-HVTiming -Action Measure -TimingLabel 'Disconnect from Hyper-V node' -Target $Node -ScriptBlock { Remove-PSSession $s }
        }
    }
}
