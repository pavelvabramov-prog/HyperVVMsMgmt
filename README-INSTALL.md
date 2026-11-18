# HyperVVMsMgmt 1.1.0

Extract the ZIP and run **Windows PowerShell 5.1 as Administrator**:

```powershell
.\Install-HyperVVMsMgmt.ps1
Import-Module HyperVVMsMgmt -RequiredVersion 1.1.0
Get-Command -Module HyperVVMsMgmt
```

Installation target: `C:\Program Files\WindowsPowerShell\Modules\HyperVVMsMgmt\1.1.0`

Other installed versions are retained. To remove or list versions:

```powershell
.\Uninstall-HyperVVMsMgmt.ps1 -List
.\Uninstall-HyperVVMsMgmt.ps1 -Version 1.1.0
.\Uninstall-HyperVVMsMgmt.ps1 -All
```

Uninstall commands that delete files require an elevated PowerShell session and confirmation.

**Note:** This release was statically checked, but runtime testing on Windows PowerShell/Hyper-V is still required.
