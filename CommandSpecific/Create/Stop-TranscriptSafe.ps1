# Purpose: Stop-TranscriptSafe - command-specific workflow.
# Maintains the existing validation, logging, and execution behavior.

# Stops transcript Safe for the calling workflow.
function Stop-TranscriptSafe {
    param([switch]$KeepTranscript)
    if ($script:session) { Remove-PSSession $script:session -ErrorAction SilentlyContinue; $script:session = $null }
    if (-not $KeepTranscript) {
        try { Stop-Transcript | Out-Null } catch { }
    }
}
