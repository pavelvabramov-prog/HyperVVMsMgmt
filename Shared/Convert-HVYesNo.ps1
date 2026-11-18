# Purpose: Convert-HVYesNo - shared helper.
# Maintains the existing validation, logging, and execution behavior.

# Converts hVYes No for the calling workflow.
function Convert-HVYesNo {
    param(
        [AllowNull()][string]$Value,
        [Parameter(Mandatory = $true)][string]$FieldName
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }

    switch ($Value.Trim().ToLower()) {
        'yes'   { return $true }
        'y'     { return $true }
        'on'    { return $true }
        'true'  { return $true }
        'no'    { return $false }
        'n'     { return $false }
        'off'   { return $false }
        'false' { return $false }
        default { throw "Invalid value for '$FieldName': '$Value'. Expected Yes/No, Y/N, On/Off, or True/False." }
    }
}
