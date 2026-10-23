"""Run a local .luau file inside Studio via the MCP execute_luau tool.
Usage: python scripts/studio_exec.py <file.luau> [Edit|Server|Client]
Prints the tool's text result. The file's last `return` value is reported by Studio."""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
import studio_mcp


def main():
    code = open(sys.argv[1], encoding="utf-8").read()
    mode = sys.argv[2] if len(sys.argv) > 2 else "Edit"
    client = studio_mcp.Client()
    result = client.call("execute_luau", {"code": code, "datamodel_type": mode}, 600).get("result", {})
    for item in result.get("content", []):
        if item.get("type") == "text":
            print(item["text"])


if __name__ == "__main__":
    main()
