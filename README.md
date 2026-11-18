# HyperVVMsMgmt

**PowerShell module for Hyper-V virtual machine lifecycle management, configuration, inventory, and tagging.**

HyperVVMsMgmt provides a unified set of PowerShell commands for managing Microsoft Hyper-V virtual machines across standalone hosts and failover clusters.

The module combines VM provisioning, guest OS configuration, safe removal, inventory reporting, and metadata tagging into a consistent command-line interface.

## Features

- **VM provisioning** — Create Hyper-V virtual machines using configuration templates.
- **Guest OS configuration** — Configure Windows guest operating systems using predefined configuration files.
- **VM removal** — Remove virtual machines and associated resources with validation and safety checks.
- **Inventory** — Collect VM information from Hyper-V hosts and failover clusters.
- **Tag management** — Read, add, remove, set, and clear VM metadata tags.
- **Cluster support** — Discover cluster nodes, resolve VM targets, and support clustered VM operations.
- **Validation mode** — Preview supported operations before making changes.
- **Logging and reporting** — Provide operational feedback, execution logs, and validation results.

## Requirements

- Windows PowerShell 5.1
- Microsoft Hyper-V management tools
- Appropriate administrative permissions on target systems
- Network connectivity and PowerShell remoting where required
- Failover Clustering management tools for cluster operations

Additional requirements depend on the operation being performed.

## Installation

The repository includes installation and uninstallation scripts:

- `Install-HyperVVMsMgmt.ps1`
- `Uninstall-HyperVVMsMgmt.ps1`

For detailed installation instructions, see [README-INSTALL.md](README-INSTALL.md).

After installation, import the module:

```powershell
Import-Module HyperVVMsMgmt
```

To list available commands:

```powershell
Get-Command -Module HyperVVMsMgmt
```

## Available commands

| Command | Description |
|---|---|
| `hv-create` | Create virtual machines from configuration files |
| `hv-config` | Configure Windows guest operating systems |
| `hv-remove` | Remove virtual machines and associated resources |
| `hv-inventory` | Retrieve Hyper-V VM inventory information |
| `hv-tags` | Manage server and VM metadata tags |
| `hv-creds` | Assist with credential management |

### VM creation

```powershell
hv-create -ConfigFile "C:\VMConfigs\Example_VM.cfg.txt" -ValidateOnly
```

Remove `-ValidateOnly` when ready to execute the operation.

### Guest OS configuration

```powershell
hv-config -ConfigFile "C:\VMConfigs\Example_OS.cfg.txt" -ValidateOnly
```

### VM removal

```powershell
hv-remove -Help
```

Consult the command help before performing destructive operations.

### Inventory

```powershell
hv-inventory -Help
```

### Tag management

```powershell
hv-tags -Action Get -ComputerName "ExampleVM" -Type HyperV -HyperVHost "ExampleHost"
```

Example: add an environment tag.

```powershell
hv-tags -Action Add -ComputerName "ExampleVM" -Type HyperV -HyperVHost "ExampleHost" -Tags "Env:TEST" -ValidateOnly
```

## Target selection and safety

When a short VM name resolves to multiple candidates, commands that support interactive selection show candidate VM names for confirmation. `hv-remove` and `hv-tags` can accept multiple selected candidates; `hv-config` resolves a single target for each configured VM. Target selection tracks VM identity (GUID) to avoid accidentally processing overlapping candidates. Always inspect the selected VM names, cluster/host and storage before Apply.

`hv-remove -KeepADAccount` prevents AD computer-account modification during removal. Use command help to review AD cleanup options before removing VMs.

`hv-tags` uses categories and values from `Config/ServerTags.config.txt`. The default generic catalog includes `Scope`, `Env`, `App`, `Role`, and `Contact`; use e.g. `Env:TEST` (not `TAG_ENV:TEST`). Custom categories/values require `-AllowCustomTags`, except categories explicitly configured for unrestricted values.

## Configuration

Module configuration files are located in the `Config` directory.

| File | Purpose |
|---|---|
| `HyperVTools.config.txt` | General module configuration |
| `HyperVInventory.config.txt` | Inventory configuration |
| `ServerTags.config.txt` | Tag categories and approved values |

Example input files are available in `InputTemplates`.

Review and customize configuration files before using the module in your environment.

## Project structure

```text
HyperVVMsMgmt/
├── Commands/
├── CommandSpecific/
│   ├── Config/
│   ├── Create/
│   ├── Inventory/
│   ├── Remove/
│   └── Tags/
├── Config/
├── InputTemplates/
├── Shared/
├── Tests/
├── HyperVVMsMgmt.psd1
├── HyperVVMsMgmt.psm1
├── Install-HyperVVMsMgmt.ps1
├── Uninstall-HyperVVMsMgmt.ps1
├── README-INSTALL.md
└── README.md
```

The module separates public command entry points, command-specific functionality, and reusable shared functions.

## Testing

The `Tests` directory contains validation and regression tests covering module architecture, VM naming, configuration parsing, inventory, tagging, and removal safety.

Tests should be executed in an appropriate test environment before deploying changes to production.

Some tests may require Hyper-V infrastructure or elevated permissions.

## Safety considerations

- Use validation mode where supported before executing changes.
- Review configuration files and target VM selection carefully.
- Confirm the target host or cluster before modifying resources.
- Exercise particular caution when removing VMs, virtual disks, or Active Directory computer objects.
- Do not store passwords or sensitive credentials in publicly shared configuration files.

## Versioning

The project uses version numbers in the format `MAJOR.MINOR.PATCH`.

Initial public release: **v1.1.0**. Current release: **v1.1.2**.

See [CHANGELOG.md](CHANGELOG.md) for changes since v1.1.0.

## Disclaimer

This software is provided as-is, without warranty. Test all operations in a non-production environment before using them on production infrastructure.

Use of this module is at your own risk.