# Regression: Create must display a clean validation failure for a shared folder override.
$moduleRoot = Split-Path $PSScriptRoot -Parent
$createSource = Get-Content -LiteralPath (Join-Path $moduleRoot 'Commands\Invoke-HVCreate.ps1') -Raw
if ($createSource -notmatch 'catch\s*\{[\s\S]*?FolderNameOverride .* is allowed only for a SINGLE VM') {
    throw 'Create parser guard is missing its controlled error handler.'
}
if ($createSource -notmatch 'Stop-TranscriptSafe -KeepTranscript:\$ExternalTranscript') {
    throw 'Create parser guard does not preserve transcript cleanup.'
}
Write-Host 'PASS: Create parser guard has a controlled validation error handler.' -ForegroundColor Green
