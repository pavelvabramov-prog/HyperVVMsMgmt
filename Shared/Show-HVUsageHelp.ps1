# Purpose: Show-HVUsageHelp - shared helper.
# Maintains the existing validation, logging, and execution behavior.

# Displays hVUsage Help for the calling workflow.
function Show-HVUsageHelp {
    param([ValidateSet('Create','Remove','Config','Creds')][string]$Command='Create')
    switch ($Command) {
        'Create' {
            Write-Host "`nhv-create (Step 2.1)`n" -ForegroundColor Cyan
            Write-Host 'USAGE: hv-create -ConfigFile <file> [-TargetHost <host-or-cluster>] [-ValidateOnly] [-AllowDuplicateBaseVMName] [-ShowTiming]'
            Write-Host '  -ConfigFile                Required VM creation definition file.'
            Write-Host '  -TargetHost               Override/select target host or cluster; mismatch prompts for choice.'
            Write-Host '  -ValidateOnly             Validate only; do not create a VM.'
            Write-Host '  -AllowDuplicateBaseVMName Allow short-name matches with confirmation; exact full-name matches remain blocked.'
            Write-Host '  -ShowTiming               Show operation timing report.'
            Write-Host '  -Help, /?                 Show help.'
            Write-Host '  Network_N and VLAN_N indices must correspond. Duplicate keys (including blank duplicate VLAN_N) are errors.'
            Write-Host 'EXAMPLES:'
            Write-Host '  hv-create -ConfigFile .\HVTSTVM055_VM_v3.0.cfg.txt -TargetHost HVTSTCLUSTER6 -ValidateOnly'
            Write-Host '  hv-create -ConfigFile .\HVTSTVM055_VM_v3.0.cfg.txt -AllowDuplicateBaseVMName'
        }
        'Config' {
            Write-Host "`nhv-config (Step 2.1)`n" -ForegroundColor Cyan
            Write-Host 'USAGE: hv-config -ConfigFile <file> [-ValidateOnly] [-StartVMIfOff] [-ADCheckMode JumpHostOnly|GuestOnly] [-AllowExistingADComputer] [-PSDirectMaxAttempts <1..1000>]'
            Write-Host '  -ConfigFile               Required guest OS configuration file.'
            Write-Host '  -ValidateOnly             Run checks without guest configuration or domain changes.'
            Write-Host '  -StartVMIfOff             Requires -ValidateOnly; start an Off VM to run guest checks; leave running.'
            Write-Host '  -ADCheckMode              JumpHostOnly (default); GuestOnly is unsupported.'
            Write-Host '  -AllowExistingADComputer  Permit existing target AD computer account (replacement/pre-staged workflows).'
            Write-Host '  -PSDirectMaxAttempts      PowerShell Direct retry limit, default 20.'
            Write-Host '  -Help, /?                Show help.'
            Write-Host 'EXAMPLES:'
            Write-Host '  hv-config -ConfigFile .\HVTSTVM055_OS_v3.0.cfg.txt -ValidateOnly -StartVMIfOff'
            Write-Host '  hv-config -ConfigFile .\HVTSTVM055_OS_v3.0.cfg.txt -AllowExistingADComputer'
            Write-Host 'WARNING: Only use -AllowExistingADComputer when the previous VM is offline and the account is ready.' -ForegroundColor Yellow
        }
        'Creds' {
            Write-Host "`nhv-creds`n" -ForegroundColor Cyan
            Write-Host 'USAGE: hv-creds [-DefaultDomain <domain>] [-Help]'
            Write-Host '  -DefaultDomain    Override the configured default domain for this invocation.'
            Write-Host '  -Help, /?         Show help without prompting for credentials.'
            Write-Host 'DESCRIPTION:'
            Write-Host '  Prompts for domain, username and password, validates credentials against AD,'
            Write-Host '  then publishes session-only credentials for Hyper-V configuration workflows.'
            Write-Host '  On validation failure, existing session credentials are preserved.'
            Write-Host 'EXAMPLES:'
            Write-Host '  hv-creds'
            Write-Host '  hv-creds -DefaultDomain CONTOSO.LOCAL'
            Write-Host '  hv-creds -Help'
            Write-Host '  hv-creds /?'
        }
        'Remove' {
            Write-Host "`nhv-remove (Step 2.1)`n" -ForegroundColor Cyan
            Write-Host 'USAGE:'
            Write-Host '  hv-remove -VMName <name>[,<name>...] -TargetHost <host-or-cluster> [-ValidateOnly] [-ResetADAccount] [-KeepADAccount] [-ADNameToCleanUp <ad-name>] [-Y] [-ForceFolderCleanup] [-ShowTiming]'
            Write-Host '  hv-remove -VMListFile <file> [-ValidateOnly] [-ResetADAccount] [-KeepADAccount] [-Y] [-ForceFolderCleanup] [-ShowTiming]'
            Write-Host 'PARAMETERS:'
            Write-Host '  -VMName              VM short name(s), or a full VM display name; with -TargetHost.'
            Write-Host '  -TargetHost          Hyper-V host or cluster to search.'
            Write-Host '  -VMListFile          Whitespace-separated VMName TargetHost [ADName] rows (see example below).'
            Write-Host '  -ValidateOnly        Inspect VM, storage and AD; no deletion.'
            Write-Host '  -ResetADAccount      Reset target AD computer account rather than delete it.'
            Write-Host '  -KeepADAccount       Preserve AD accounts in either mode; incompatible with -ResetADAccount and -ADNameToCleanUp.'
            Write-Host '  -ADNameToCleanUp     Explicit AD computer account name; single -VMName only; incompatible with -KeepADAccount and -VMListFile.'
            Write-Host '  -Y                   Skip batch-wide VM removal confirmation (extra-file prompts remain).'
            Write-Host '  -ForceFolderCleanup  Requires -Y; deletes all extra files without prompting. CAUTION: files may belong to other VMs.'
            Write-Host '  -ShowTiming          Show timing measurements and summary.'
            Write-Host '  -Help, /?            Show help.'
            Write-Host 'AD CLEANUP: Defaults to the requested VM name ONLY when it fully matches configured VMNaming.ShortNamePattern; never inferred from a display name.'
            Write-Host '  Nonmatching names skip AD cleanup unless an explicit AD name is supplied. AD deletion follows verified VM removal.'
            Write-Host 'LIST FILE FORMAT (plain text, whitespace-separated; header optional):'
            Write-Host '  VMName TargetHost ADName'
            Write-Host '  HVTSTVM040 HVTSTCLUSTER6'
            Write-Host '  HVTSTVM041 HVTSTCLUSTER6'
            Write-Host '  "HVTSTVM055 - My Test VM" HVTSTCLUSTER6 HVTSTVM055'
            Write-Host '  HVTSTWS123 HVTSTVH050'
            Write-Host '  One VM per line; optional ADName overrides AD target; quote VM names with spaces; blank lines and # comments ignored.'
            Write-Host 'EXAMPLES:'
            Write-Host '  hv-remove -VMName HVTSTVM042 -TargetHost HVTSTCLUSTER6 -ValidateOnly'
            Write-Host '  hv-remove -VMName HVTSTVM042 -TargetHost HVTSTCLUSTER6 -ADNameToCleanUp HVTSTVM042TEST'
            Write-Host '  hv-remove -VMListFile C:\Temp\VMsToRemove.txt -ValidateOnly'
            Write-Host '  hv-remove -VMName HVTSTVM041 -TargetHost HVTSTCLUSTER6 -KeepADAccount'
        }
    }
}
