"""Minimal stdio client for the Roblox Studio MCP server (StudioMCP.exe), used to playtest ARMFORGE from a terminal.

Studio must be running with the place open; the server connects to it a few seconds after start. Examples:

    python scripts/studio_mcp.py list                                  # tool names
    python scripts/studio_mcp.py get_studio_state
    python scripts/studio_mcp.py start_stop_play '{"is_start": true}'
    python scripts/studio_mcp.py execute_luau '{"code": "return 1+1", "datamodel_type": "Server"}'
    python scripts/studio_mcp.py screen_capture '{"camera_position":[0,8,-80],"look_at_position":[0,13,-227],"capture_id":"x"}'

The studio id is filled in automatically (the first connected Studio). Images are written to $MCP_IMG (default capture.png).
Set STUDIO_MCP to the StudioMCP.exe path if it is not under %LOCALAPPDATA%/Roblox/Versions.
"""
import base64
import glob
import json
import os
import queue
import subprocess
import sys
import threading
import time


def find_exe():
    explicit = os.environ.get("STUDIO_MCP")
    if explicit:
        return explicit
    found = sorted(glob.glob(os.path.expandvars(r"%LOCALAPPDATA%\Roblox\Versions\*\StudioMCP.exe")), key=os.path.getmtime)
    if not found:
        sys.exit("StudioMCP.exe not found; set STUDIO_MCP")
    return found[-1]


class Client:
    def __init__(self):
        self.p = subprocess.Popen([find_exe()], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        self.q = queue.Queue()
        self.id = 0
        threading.Thread(target=self._read, daemon=True).start()
        self.req("initialize", {"protocolVersion": "2025-03-26", "capabilities": {}, "clientInfo": {"name": "armforge", "version": "1"}})
        self._send({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})
        self.sid = None

    def _read(self):
        for line in self.p.stdout:
            try:
                self.q.put(json.loads(line))
            except ValueError:
                pass

    def _send(self, message):
        self.p.stdin.write((json.dumps(message) + "\n").encode())
        self.p.stdin.flush()

    def req(self, method, params, timeout=300):
        self.id += 1
        mine = self.id
        self._send({"jsonrpc": "2.0", "id": mine, "method": method, "params": params})
        end = time.time() + timeout
        while time.time() < end:
            try:
                message = self.q.get(timeout=1)
            except queue.Empty:
                continue
            if message.get("id") == mine:
                return message
        raise TimeoutError(method)

    def studio(self):
        if self.sid:
            return self.sid
        for _ in range(40):
            result = self.req("tools/call", {"name": "list_roblox_studios", "arguments": {}})
            studios = json.loads(result["result"]["content"][0]["text"])["studios"]
            if studios:
                self.sid = studios[0]["id"]
                return self.sid
            time.sleep(0.5)
        sys.exit("no Studio connected")

    def call(self, name, args, timeout=300):
        if name != "list_roblox_studios" and "studio_id" not in args:
            args = dict(args, studio_id=self.studio())
        return self.req("tools/call", {"name": name, "arguments": args}, timeout)


def main():
    client = Client()
    if len(sys.argv) < 2 or sys.argv[1] == "list":
        for tool in client.req("tools/list", {})["result"]["tools"]:
            print(tool["name"])
        return
    args = json.loads(sys.argv[2]) if len(sys.argv) > 2 else {}
    result = client.call(sys.argv[1], args).get("result", {})
    for item in result.get("content", []):
        if item.get("type") == "text":
            print(item["text"])
        elif item.get("type") == "image":
            path = os.environ.get("MCP_IMG", "capture.png")
            with open(path, "wb") as handle:
                handle.write(base64.b64decode(item["data"]))
            print("image saved:", path)


if __name__ == "__main__":
    main()
