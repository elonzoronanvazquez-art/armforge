# Generates a Rojo sourcemap, then runs luau-lsp's analyzer over src/ in strict mode,
# once with the old Luau solver and once with the new one (Studio may use either).
# Usage: powershell -ExecutionPolicy Bypass -File scripts/typecheck.ps1
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$rojo = if (Get-Command rojo -ErrorAction SilentlyContinue) { 'rojo' } else { 'C:\Tools\Rojo\rojo.exe' }
$lsp = 'C:\Tools\luau-lsp\luau-lsp.exe'
$defs = 'C:\Tools\luau-lsp\globalTypes.d.luau'

& $rojo sourcemap default.project.json --output sourcemap.json
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$failed = $false
foreach ($solver in 'false', 'true') {
    Write-Host "== luau-lsp analyze (LuauSolverV2=$solver)"
    & $lsp analyze --definitions=$defs --sourcemap=sourcemap.json --base-luaurc=.luaurc "--flag:LuauSolverV2=$solver" src
    if ($LASTEXITCODE -ne 0) { $failed = $true }
}
exit ([int]$failed)
