#!/usr/bin/env bash
# Stop play, hot-sync scripts into Studio, restart play, wait and show relevant output.
# Usage: bash scripts/reload.sh [waitSeconds=35]
cd "$(dirname "$0")/.." || exit 1
export PYTHONIOENCODING=utf-8
python scripts/studio_mcp.py start_stop_play '{"is_start": false}' >/dev/null
python scripts/studio_sync.py
python scripts/studio_mcp.py start_stop_play '{"is_start": true}' >/dev/null
sleep "${1:-35}"
python scripts/console.py 60 --all | grep -v -E "^\s*$"
