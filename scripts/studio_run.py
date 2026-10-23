"""Run one Luau snippet (read from stdin or a file) in a datamodel and print the result.
Usage: python scripts/studio_run.py Server|Client|Edit [file.luau]   (stdin if no file)"""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
import studio_mcp

mode = sys.argv[1]
code = open(sys.argv[2], encoding="utf-8").read() if len(sys.argv) > 2 else sys.stdin.read()
client = studio_mcp.Client()
res = client.call("execute_luau", {"code": code, "datamodel_type": mode}, 300).get("result", {})
for item in res.get("content", []):
    if item.get("type") == "text":
        print(item["text"])
