#!/usr/bin/env bash
# Deduplicated luau-lsp output (single solver). Usage: bash scripts/tc.sh
cd "$(dirname "$0")/.." || exit 1
rojo sourcemap default.project.json --output sourcemap.json >/dev/null
/c/Tools/luau-lsp/luau-lsp.exe analyze --definitions=/c/Tools/luau-lsp/globalTypes.d.luau --sourcemap=sourcemap.json --base-luaurc=.luaurc "--flag:LuauSolverV2=false" src 2>&1 | python scripts/tc_filter.py
