$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$create = Get-Content (Join-Path $root 'Commands/Invoke-HVCreate.ps1') -Raw
$engine = Get-Content (Join-Path $root 'Commands/New-HVVM.ps1') -Raw
$log = Get-Content (Join-Path $root 'Shared/Start-HVExecutionLog.ps1') -Raw
$stop = Get-Content (Join-Path $root 'CommandSpecific/Create/Stop-TranscriptSafe.ps1') -Raw
if ($create -notmatch 'Start-Transcript' -or $create -notmatch 'Invoke-HVTiming -Action Report' -or $create -notmatch 'Stop-Transcript') { throw 'Public Create transcript lifecycle incomplete.' }
if ($create -notmatch '-ExternalTranscript' -or $engine -notmatch '\[switch\]\$ExternalTranscript') { throw 'External transcript handoff missing.' }
if ($log -notmatch 'Create_\$stamp\.log' -or $log -notmatch 'StandardName') { throw 'Create timestamp naming missing.' }
if ($stop -notmatch 'KeepTranscript') { throw 'Early-return transcript handling missing.' }
$errors = @()
Get-ChildItem $root -Recurse -Filter '*.ps1' | ForEach-Object {
    $tokens = $null; $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors) { $errors += "$($_.FullName): $($parseErrors -join '; ')" }
}
if ($errors.Count) { throw ($errors -join "`n") }
if (-not (Get-Command hv-create).Parameters.ContainsKey('ShowTiming')) { throw 'hv-create -ShowTiming missing' }
Write-Host 'PASS: Step 8.4 Create transcript lifecycle, naming, timing, and source syntax.' -ForegroundColor Green
