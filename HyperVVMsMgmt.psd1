@{
 RootModule = 'HyperVVMsMgmt.psm1'
 ModuleVersion = '1.1.2'
 GUID = 'dbfddf6d-0d44-4b7e-a532-f14b1c7f54aa'
 Author = 'HyperVVMsMgmt'
 Description = 'HyperVVMsMgmt: Hyper-V VM creation, configuration, removal, credentials, tags and inventory.'
 PowerShellVersion = '5.1'
 FunctionsToExport = @('Invoke-HVCreate','Invoke-HVRemove','Invoke-HVConfig','Invoke-HVCreds','Invoke-HVTags','Invoke-HVInventory')
 AliasesToExport = @('hv-create','hv-remove','hv-config','hv-creds','hv-tags','hv-inventory')
 CmdletsToExport = @()
 VariablesToExport = @()
 PrivateData = @{
  BuildId = '1.1.2-20261118'
 }
}
