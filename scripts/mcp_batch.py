"""Run several Studio MCP calls over one connection. Usage: python scripts/mcp_batch.py calls.json
calls.json = [{"name": "...", "args": {...}}, ...]; prints each text result."""
import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
import studio_mcp


def main():
    calls = json.load(open(sys.argv[1], encoding="utf-8"))
    client = studio_mcp.Client()
    for call in calls:
        result = client.call(call["name"], call.get("args", {}), call.get("timeout", 300)).get("result", {})
        print("##", call["name"])
        for item in result.get("content", []):
            if item.get("type") == "text":
                print(item["text"])
            elif item.get("type") == "image":
                path = os.environ.get("MCP_IMG", "capture.png")
                import base64
                open(path, "wb").write(base64.b64decode(item["data"]))
                print("image saved:", path)


if __name__ == "__main__":
    main()
