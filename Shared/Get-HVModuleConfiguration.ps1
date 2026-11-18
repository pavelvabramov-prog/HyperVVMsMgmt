# Reads mandatory module-wide INI-style configuration (no external dependencies).
function Get-HVModuleConfiguration {
    $path = Join-Path $script:moduleRoot 'Config\HyperVTools.config.txt'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Module configuration not found: $path" }
    $values = @{}
    $section = ''
    $lineNumber = 0
    foreach ($line in (Get-Content -LiteralPath $path -ErrorAction Stop)) {
        $lineNumber++
        $line = $line.Trim()
        if (-not $line -or $line.StartsWith('#') -or $line.StartsWith(';')) { continue }
        if ($line -match '^\[([A-Za-z][A-Za-z0-9]*)\]$') { $section = $Matches[1]; continue }
        if ($line -notmatch '^([A-Za-z][A-Za-z0-9]*)\s*=\s*(.*)$' -or -not $section) {
            throw "Invalid configuration at ${path}:$lineNumber"
        }
        $key = "$section.$($Matches[1])"
        if ($values.ContainsKey($key)) { throw "Duplicate configuration key: $key" }
        $values[$key] = $Matches[2].Trim()
    }
    foreach ($required in @('General.DefaultDomain','Logging.LogPath','VMNaming.ShortNamePattern','Tags.WindowsRegistryPath','Tags.LinuxMetadataFile')) {
        if (-not $values.ContainsKey($required) -or [string]::IsNullOrWhiteSpace($values[$required])) { throw "Missing required module configuration: $required" }
    }
    if (-not $values['Tags.WindowsRegistryPath'].StartsWith('HKLM:\SOFTWARE\', [StringComparison]::OrdinalIgnoreCase) -or
        $values['Tags.WindowsRegistryPath'] -notmatch '^[A-Za-z0-9_:\\-]+$') {
        throw 'Tags.WindowsRegistryPath must be an HKLM:\SOFTWARE registry key.'
    }
    if ($values['Tags.LinuxMetadataFile'] -notmatch '^/etc/[A-Za-z0-9._-]+$' -or $values['Tags.LinuxMetadataFile'] -match '/\.\.') {
        throw 'Tags.LinuxMetadataFile must be a simple absolute file path under /etc.'
    }
    return [pscustomobject]@{
        DefaultDomain = $values['General.DefaultDomain']
        LogPath = $values['Logging.LogPath']
        CreateLogPath = $values['Logging.CreateLogPath']
        ConfigLogPath = $values['Logging.ConfigLogPath']
        RemoveLogPath = $values['Logging.RemoveLogPath']
        VMNaming = [pscustomobject]@{ ShortNamePattern = $values['VMNaming.ShortNamePattern'] }
        WindowsRegistryPath = $values['Tags.WindowsRegistryPath']
        LinuxMetadataFile = $values['Tags.LinuxMetadataFile']
    }
}
