# Runs the Lune test suite from the repo root.
# Usage: powershell -ExecutionPolicy Bypass -File scripts/test.ps1 [filter]
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$lune = if (Get-Command lune -ErrorAction SilentlyContinue) { 'lune' } else { 'C:\Tools\Lune\lune.exe' }
& $lune run tests/run @args
exit $LASTEXITCODE
