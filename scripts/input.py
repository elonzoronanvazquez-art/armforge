"""Drive the playtest client's mouse/keyboard through Studio MCP.
Usage: python scripts/input.py mouse '<json action list>'   |   python scripts/input.py key '<json action list>'
Example: python scripts/input.py mouse '[{"action":"mouseButtonDown","mouse_button":"left","x":580,"y":350},{"action":"wait","wait_time_ms":1500},{"action":"mouseButtonUp","mouse_button":"left"}]'"""
import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
import studio_mcp

kind = sys.argv[1]
actions = json.loads(sys.argv[2])
tool = "user_mouse_input" if kind == "mouse" else "user_keyboard_input"
client = studio_mcp.Client()
res = client.call(tool, {"actions": actions, "datamodel_type": "Client"}, 120).get("result", {})
for item in res.get("content", []):
    if item.get("type") == "text":
        print(item["text"])
