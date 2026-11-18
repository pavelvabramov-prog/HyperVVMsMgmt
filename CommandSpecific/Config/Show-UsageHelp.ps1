# Purpose: Show-UsageHelp - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Displays usage Help for the calling workflow.
function Show-UsageHelp {
    $scriptName = if ($PSCommandPath) { Split-Path -Leaf $PSCommandPath } else { 'Set-HyperVGuestWindowsConfig-MultiVM_V2.5_JumpHost.ps1' }

    Write-Host ""
    Write-Host "$scriptName" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage:" -ForegroundColor Cyan
    Write-Host "  .\$scriptName -ConfigFile <config.txt> [-ValidateOnly] [-StartVMIfOff] [-ADCheckMode JumpHostOnly|GuestOnly] [-AllowExistingADComputer] [-PSDirectMaxAttempts 20]"
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Cyan
    Write-Host "  .\$scriptName -ConfigFile .\VM_OS_cfg.txt -ValidateOnly"
    Write-Host "  .\$scriptName -ConfigFile .\VM_OS_cfg.txt -ValidateOnly -StartVMIfOff"
    Write-Host "  .\$scriptName -ConfigFile .\VM_OS_cfg.txt"
    Write-Host "  .\$scriptName -ConfigFile .\VM_OS_cfg.txt -AllowExistingADComputer"
    Write-Host "  .\$scriptName -Help   (or /?)"
    Write-Host ""
    Write-Host "Parameters:" -ForegroundColor Cyan
    Write-Host "  -ConfigFile                  Path to the VM guest OS configuration file."
    Write-Host "  -Help                       Display this help (also supports /?)."
    Write-Host "  -ValidateOnly                Validate configuration/runtime readiness only; do not apply changes."
    Write-Host "  -StartVMIfOff               With -ValidateOnly, start selected VM only if Off; leave it running. Refuses Paused/Saved states."
    Write-Host "  -ADCheckMode JumpHostOnly     Check target-domain AD computer/OU on the launching machine. Default."
    Write-Host "  -ADCheckMode GuestOnly        Not supported yet (execution is blocked)."
    Write-Host "  -AllowExistingADComputer      Allows domain join when the target AD computer account already exists."
    Write-Host "  -PSDirectMaxAttempts          Maximum first-boot PowerShell Direct connection attempts (default: 20)."
    Write-Host ""
    Write-Host "AllowExistingADComputer warning:" -ForegroundColor Yellow
    Write-Host "  Use only for VM replacement/pre-staged account workflows."
    Write-Host "  Be sure the old VM is offline and the AD computer account was reset or pre-staged."
    Write-Host "  With this switch, Apply mode attempts the domain join without an extra Y/N prompt."
    Write-Host ""
}
