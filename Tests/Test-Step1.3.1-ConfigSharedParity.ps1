$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'Build-HVConfigSharedPayload.ps1') -VerifyOnly
if (-not $?) { throw 'Config shared payload verification failed' }
