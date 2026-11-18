INPUT TEMPLATES — HyperVVMsMgmt Step 1.4

This folder contains sample input files for HyperVVMsMgmt commands.
The names, passwords, addresses, paths and other values in the VM and OS examples are intentionally generic examples. They are not production settings.
These templates are not automatically loaded by the module. Copy and edit them for your environment before use.

FILES
  01_EXMPLCONF_VM_v3.9.cfg.txt  - Example VM creation configuration for hv-create -ConfigFile
  02_EXMPLCONF_OS_v3.9.cfg.txt  - Example guest OS configuration for hv-config -ConfigFile
  03_hv-remove_VMList.txt       - Example VM removal list for hv-remove -VMListFile
  04_hv-tags_ServerList.csv     - Header-only bulk tagging list for hv-tags -ServerListFile
  README.txt                    - This guide

USAGE
  hv-create -ConfigFile 'C:\Temp\VM.cfg.txt' -ValidateOnly
  hv-config -ConfigFile 'C:\Temp\OS.cfg.txt' -ValidateOnly
  hv-remove -VMListFile 'C:\Temp\VMList.txt' -ValidateOnly
  hv-tags -ServerListFile 'C:\Temp\Tags.csv' -Set -ValidateOnly
  hv-inventory -ServerList HVTSTCLUSTER6 -ReportProfile Short -ReportFile 'C:\Temp\Inventory.csv'

NOTES
  - The VM and OS configuration files are examples: review and adapt all relevant fields before running commands.
  - The removal list contains commented examples; add actual VM/target-host entries to use it.
  - The Tags CSV contains column headers only; add rows for the servers you want to process.
  - For hv-remove, quote VM display names containing spaces.
  - hv-inventory -ServerList accepts server/cluster names, not a filename; -ReportFile specifies an output CSV.
  - hv-creds does not take an input file.
  - Active module settings live in the module's Config folder, not in InputTemplates. In particular:
      Config\HyperVTools.config.txt      - Shared module settings
      Config\ServerTags.config.txt        - Tags rules/catalog
      Config\HyperVInventory.config.txt  - Inventory report profiles
    These configuration files are not duplicated in InputTemplates.
  - Use -ValidateOnly where supported before making changes. Review results carefully before applying operations.
