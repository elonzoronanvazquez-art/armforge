"""Deduplicates and shortens luau-lsp analyze output read from stdin (the analyzer repeats each diagnostic per module)."""
import re
import sys

seen = set()
for line in sys.stdin:
    line = line.rstrip()
    if line.startswith("[INFO]") or line.startswith("[WARN]"):
        continue
    line = line.replace("c:\\repo\\armforge\\", "").replace("\\", "/")
    line = re.sub(r" \[game/[^\]]*\]", "", line)
    if line not in seen:
        seen.add(line)
        print(line)
