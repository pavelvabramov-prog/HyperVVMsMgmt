# Purpose: Convert-ToBoolFromYesNo - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Converts to Bool From Yes No for the calling workflow.
function Convert-ToBoolFromYesNo {
    param([string]$Value, [string]$FieldName = 'Value')
    # Compatibility adapter: v2.5 accepted Yes/No, On/Off and True/False,
    # but not Y/N. Keep that validation contract while reusing shared logic.
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    if ($Value.Trim().ToLowerInvariant() -in @('y','n')) {
        throw "Invalid value '$Value' for $FieldName"
    }
    try { return Convert-HVYesNo -Value $Value -FieldName $FieldName }
    catch { throw "Invalid value '$Value' for $FieldName" }
}
