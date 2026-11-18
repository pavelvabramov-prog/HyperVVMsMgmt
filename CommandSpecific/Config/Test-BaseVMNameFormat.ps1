# Purpose: Test-BaseVMNameFormat - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Checks base VMName Format for the calling workflow.
function Test-BaseVMNameFormat {
    param([string]$Name, [string]$Context)
    Test-HVShortVMName -BaseVMName $Name -Pattern '^[A-Za-z0-9]{10}$' -Context $Context
}
