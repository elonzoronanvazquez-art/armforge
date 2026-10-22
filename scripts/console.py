"""Fetch Studio's output through MCP and show only ARMFORGE-relevant lines (drops CorePackages / UIBlox noise).
Usage: python scripts/console.py [maxLines=60] [--all]"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import studio_mcp

NOISE = ("CorePackages", "UIBlox", "FoundationProvider", "ReactReconciler", "Scheduler", "ContentId: rbxassetid://203785492")
KEEP = ("ARMFORGE", "Armforge", "ServerScriptService", "StarterPlayer", "rror", "attempt to", "Infinite yield", "stack", "failed")


def main():
    limit = 60
    show_all = "--all" in sys.argv
    for arg in sys.argv[1:]:
        if arg.isdigit():
            limit = int(arg)
    client = studio_mcp.Client()
    result = client.call("get_console_output", {}).get("result", {})
    text = "\n".join(i.get("text", "") for i in result.get("content", []) if i.get("type") == "text")
    lines = []
    for line in text.splitlines():
        if not line.strip() or any(n in line for n in NOISE):
            continue
        if show_all or any(k in line for k in KEEP):
            lines.append(line)
    print("\n".join(lines[-limit:]))


if __name__ == "__main__":
    main()
