"""Hold the playtest camera at a pose (needs the Studio-only DevCamController). Usage:
  cam.py <px> <py> <pz> <lx> <ly> <lz> [fov]    absolute world positions
  cam.py follow <dx> <dy> <dz> [fov]             offset in the character's local space (x right, y up, z BACK), looking at the character
  cam.py reset"""
import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
import studio_mcp

a = sys.argv[1:]
if a[0] == "reset":
    code = "workspace:SetAttribute('AF_DevCam', nil); workspace.CurrentCamera.CameraType = Enum.CameraType.Custom; return 'reset'"
elif a[0] == "follow":
    dx, dy, dz = a[1:4]
    fov = a[4] if len(a) > 4 else "70"
    code = f'''local hrp = game.Players.LocalPlayer.Character.HumanoidRootPart
workspace:SetAttribute("AF_DevFov", {fov})
local pos = hrp.Position + hrp.CFrame:VectorToWorldSpace(Vector3.new({dx},{dy},{dz}))
workspace:SetAttribute("AF_DevCam", CFrame.lookAt(pos, hrp.Position + Vector3.new(0, 1.2, 0)))
return "ok" '''
else:
    px, py, pz, lx, ly, lz = a[:6]
    fov = a[6] if len(a) > 6 else "70"
    code = f'''workspace:SetAttribute("AF_DevFov", {fov})
workspace:SetAttribute("AF_DevCam", CFrame.lookAt(Vector3.new({px},{py},{pz}), Vector3.new({lx},{ly},{lz})))
return "ok" '''
client = studio_mcp.Client()
res = client.call("execute_luau", {"code": code, "datamodel_type": "Client"}, 60).get("result", {})
for item in res.get("content", []):
    if item.get("type") == "text":
        print(item["text"])
