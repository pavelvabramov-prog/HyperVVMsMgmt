# Invocation-local identity state. Never persist across command runs.
function New-HVSelectionContext {
    [pscustomobject]@{ Selected = @{}; Excluded = @{} }
}
