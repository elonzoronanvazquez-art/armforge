"""Call the Studio-only dev bridge (server/Dev/DevTools) during a playtest.
Usage: python scripts/dev.py <command> [jsonArg ...]      e.g.  python scripts/dev.py coins 500
Commands: coins shards xp level giveArm equip unlockAll rebirths booster tpToRock tp rockInfo state hrp spawnRock"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import studio_mcp

cmd = sys.argv[1]
args = []
for a in sys.argv[2:]:
    try:
        args.append(json.loads(a))
    except ValueError:
        args.append(a)
lua_args = ", ".join(json.dumps(a) for a in args)
code = f'''
local r = game.ServerStorage.ArmforgeDev:Invoke({json.dumps(cmd)}{", " + lua_args if lua_args else ""})
if type(r) == "table" then return game:GetService("HttpService"):JSONEncode(r) end
return tostring(r)
'''
client = studio_mcp.Client()
res = client.call("execute_luau", {"code": code, "datamodel_type": "Server"}, 120).get("result", {})
for item in res.get("content", []):
    if item.get("type") == "text":
        print(item["text"])
