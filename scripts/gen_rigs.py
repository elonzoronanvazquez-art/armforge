"""Generate SEGMENTED creature meshes (torso, head, arms, legs as separate MeshParts) through Studio's generate_mesh tool so the
client can animate the limbs. One at a time (parallel jobs are rejected); Studio must be in Edit mode with no other MCP call in flight.

Usage:  python scripts/gen_rigs.py [name ...]     (no names = every rig that has not completed yet)
State:  docs/generated_assets.json  name -> {prompt, status, parts: [{name, mesh, tex, size, cf, class}], bbox}
        `cf` is the part's CFrame relative to the model's bounding-box centre (12 components, Roblox order), so the builder can
        reassemble the creature exactly as generated. scripts/export_rigs.py turns this into src/shared/Config/CreatureRigs.luau.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import studio_mcp

STATE = os.path.join(os.path.dirname(__file__), "..", "docs", "generated_assets.json")

BIPED = "torso, head, left arm, right arm, left leg, right leg"
QUAD = "body, head, tail, front left leg, front right leg, back left leg, back right leg"

RIGS = {
    # Forgeheart
    "RigBrute": ("a heavy furnace forged iron golem with riveted rust orange plates and a glowing furnace window in the chest, standing upright, stylized game monster", (5, 6.5, 3.2), 9000, BIPED),
    "RigColossus": ("a massive hulking stone golem built from stacked grey granite slabs with spikes on its shoulders and glowing orange cracks in its chest, standing upright, stylized game boss", (7, 9, 4.2), 12000, BIPED),
    "RigAnvilKing": ("a colossal dark iron armored king golem wearing an anvil shaped crown, a glowing molten furnace window in the chest, spiked shoulder armor, standing upright, stylized game boss", (7, 9.5, 4.4), 14000, BIPED),
    # Crystalfall
    "RigWarden": ("a heavy amethyst crystal armored sentinel golem with deep violet crystal plates and a glowing pink core in the chest, standing upright, stylized game monster", (5, 6.5, 3.2), 9000, BIPED),
    "RigChoir": ("a tall cathedral like crystal golem made of pale blue translucent crystal spires and frozen ice plates with a glowing gold core in the chest, standing upright, stylized game monster", (7, 9.5, 4.2), 12000, BIPED),
    "RigLyrae": ("a towering frozen crystal golem queen in white ice armor with long crystal spires rising from the shoulders like organ pipes and a glowing cyan core in the chest, standing upright, stylized game boss", (7, 10, 4.4), 14000, BIPED),
    # Emberfang
    "RigAshHound": ("a lean four legged black basalt hound with glowing ember cracks along its back and a pointed snout, stylized game monster", (3, 3.2, 5.5), 9000, QUAD),
    "RigMagmaGolem": ("a squat cooled lava crust golem with glowing molten cracks and chunky fists, standing upright, stylized game monster", (5, 6.5, 3.4), 9000, BIPED),
    "RigObsidian": ("a hulking volcanic glass golem in black obsidian armor with glowing violet cracks and a tall hooded head, standing upright, stylized game monster", (6.5, 9, 4.0), 12000, BIPED),
    "RigCinderjaw": ("a giant black basalt and molten lava golem with a huge jawed head full of glowing fire and spiked shoulders, standing upright, stylized game boss", (7.5, 10, 5), 14000, BIPED),
}

# Studio inserts the finished model into Workspace; claim the newest unclaimed one and describe every MeshPart in it.
CLAIM = """
local name = "%s"
local found
for _, child in workspace:GetChildren() do
	if child:IsA("Model") and child:GetAttribute("AF_Name") == nil then
		found = child
	end
end
if not found then return "{}" end
found:SetAttribute("AF_Name", name)
found.Name = name
local bbox, bsize = found:GetBoundingBox()
local out = {}
for _, d in found:GetDescendants() do
	if d:IsA("MeshPart") then
		local rel = bbox:ToObjectSpace(d.CFrame)
		table.insert(out, {name = d.Name, mesh = d.MeshId, tex = d.TextureID, size = {d.Size.X, d.Size.Y, d.Size.Z}, cf = {rel:GetComponents()}, class = d.ClassName})
	end
end
return game:GetService("HttpService"):JSONEncode({parts = out, bbox = {bsize.X, bsize.Y, bsize.Z}})
"""


def main():
    state = {}
    if os.path.exists(STATE):
        state = json.load(open(STATE, encoding="utf-8"))
    wanted = sys.argv[1:] or [n for n in RIGS if state.get(n, {}).get("status") != "Completed"]
    client = studio_mcp.Client()
    for name in wanted:
        prompt, size, tris, parts = RIGS[name]
        args = {
            "textPrompt": prompt,
            "size": {"x": size[0], "y": size[1], "z": size[2]},
            "maxTriangles": tris,
            "segmentation": "explicit",
            "partNames": parts,
        }
        try:
            result = client.call("generate_mesh", args, 1500).get("result", {})
        except TimeoutError:
            state[name] = {"prompt": prompt, "status": "Timeout"}
            print(name, "timeout", flush=True)
            continue
        entry = {"prompt": prompt, "partNames": parts}
        if result.get("isError"):
            entry["status"] = "Failed"
            entry["error"] = (result.get("content") or [{}])[0].get("text", "")
            print(name, "FAILED", entry["error"], flush=True)
        else:
            res = client.call("execute_luau", {"code": CLAIM % name, "datamodel_type": "Edit"}, 120).get("result", {})
            try:
                data = json.loads(res["content"][0]["text"])
            except Exception:
                data = {}
            entry["status"] = "Completed" if data.get("parts") else "NoParts"
            entry["parts"] = data.get("parts", [])
            entry["bbox"] = data.get("bbox")
            print(name, entry["status"], [p["name"] for p in entry["parts"]], flush=True)
        state[name] = entry
        json.dump(state, open(STATE, "w", encoding="utf-8"), indent=1)


if __name__ == "__main__":
    main()
