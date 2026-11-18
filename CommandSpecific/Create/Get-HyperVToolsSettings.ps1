# Retrieves hyper VTools Settings for the calling workflow.
function Get-HyperVToolsSettings {
    param([string]$RepositoryRoot)
    $settings = Get-HVModuleConfiguration
    $logPath = if (-not [string]::IsNullOrWhiteSpace([string]$settings.CreateLogPath)) { [string]$settings.CreateLogPath } else { [string]$settings.LogPath }
    if ([string]::IsNullOrWhiteSpace($logPath)) { throw 'HyperVTools CreateLogPath and LogPath are both empty.' }
    if (-not [System.IO.Path]::IsPathRooted($logPath)) { throw "HyperVTools log directory must be absolute: $logPath" }
    $pattern = [string]$settings.VMNaming.ShortNamePattern
    if ([string]::IsNullOrWhiteSpace($pattern)) { throw 'HyperVTools VMNaming.ShortNamePattern is missing. Run Set-HyperVToolsConfig v1.1.' }
    try { [void][regex]::new($pattern) }
    catch { throw "Invalid VMNaming.ShortNamePattern in HyperVTools configuration: $($_.Exception.Message)" }
    [pscustomobject]@{ LogPath = $logPath; ShortNamePattern = $pattern }
}
