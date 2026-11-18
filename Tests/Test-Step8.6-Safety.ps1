# Read-only static safety assertions; no Hyper-V changes.
$root = Split-Path -Parent $PSScriptRoot
$inv = Get-Content (Join-Path $root 'CommandSpecific\Remove\Node-Get-VMDataInventory.ps1') -Raw
$node = Get-Content (Join-Path $root 'CommandSpecific\Remove\Remove-NodeEngine.ps1') -Raw
$wait = Get-Content (Join-Path $root 'CommandSpecific\Remove\Node-Wait-VMFileHandlesReleased.ps1') -Raw
$remove = Get-Content (Join-Path $root 'Commands\Invoke-HVRemove.ps1') -Raw
if ($inv -match 'knownVmRuntimeExtensions|Get-ChildItem[^\r\n]*-Recurse') { throw 'Unsafe extension-based/recursive file discovery found' }
if ($inv -notmatch 'Get-VMHardDiskDrive|Get-VMSnapshot|VM.Id') { throw 'Hyper-V identity inventory missing' }
if ($wait -notmatch 'RetryCount=5') { throw 'Five-attempt limit missing' }
if ($node -notmatch 'N/A \(standalone host\)') { throw 'Standalone reporting missing' }
if ($remove -notmatch 'ForceFolderCleanup -and -not \$Y') { throw 'ForceFolderCleanup validation missing' }
Write-Host 'PASS: Step 8.6 static safety checks' -ForegroundColor Green
