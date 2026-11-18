# HyperVVMsMgmt v1.1.2 — Installation

Extract the full release ZIP, open **Windows PowerShell 5.1 as Administrator**, and run:

```powershell
.\Install-HyperVVMsMgmt.ps1
Import-Module HyperVVMsMgmt -RequiredVersion 1.1.2
Get-Command -Module HyperVVMsMgmt
```

The installer reads the version from `HyperVVMsMgmt.psd1` and installs into:

`C:\Program Files\WindowsPowerShell\Modules\HyperVVMsMgmt\1.1.2`

Existing versions are retained. The installer will **not overwrite** an already-installed 1.1.2 folder. To list or uninstall versions:

```powershell
.\Uninstall-HyperVVMsMgmt.ps1 -List
.\Uninstall-HyperVVMsMgmt.ps1 -Version 1.1.2
.\Uninstall-HyperVVMsMgmt.ps1 -All
```

Uninstall operations that delete files require elevation and confirmation. Review the generic configuration files in `Config/` before using the module in your environment. Do not publish organization-specific configuration or credentials.

**Testing:** Windows PowerShell 5.1 integration tests were performed in a test Hyper-V cluster for `hv-create`, `hv-config`, `hv-remove`, `hv-tags`, and `hv-inventory`. These results do not guarantee behavior in other environments. The release candidate has not been independently executed in this packaging environment.
