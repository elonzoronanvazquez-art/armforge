"""Generate the AI meshes used by ARMFORGE through Studio's generate_mesh tool, one at a time.

Usage:  python scripts/gen_assets.py [name ...]     (no names = every asset that has not succeeded yet)
State:  docs/generated_assets.json  name -> {prompt, status, publishedAssetId, meshId, textureId, size}

Each generation runs synchronously (parallel jobs were rejected with "Unable to generate Model"). After a
generation succeeds, the new Model that Studio inserted into Workspace is renamed to the asset name and tagged with
the attribute AF_Name, and its MeshPart's real MeshId / TextureID / Size are recorded. Those ids are what the game
references (see src/shared/Config/Assets.luau).
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import studio_mcp

STATE = os.path.join(os.path.dirname(__file__), "..", "docs", "generated_assets.json")

PROMPTS = {
    # rock chunks (neutral grey so the game can tint every layer)
    "ShardA": ("a single chunky faceted stone rock fragment with flat cleaved faces, neutral mid gray, low poly stylized game asset", (3, 2.4, 3), 1500),
    "ShardB": ("a flat angular broken slab of stone, neutral gray, low poly stylized game asset", (4, 1.6, 3), 1500),
    # low-poly rock chunks for the destruction system (many of these are on screen at once, so triangle count matters)
    "RockA": ("a rugged angular chunk of stone with chipped flat facets, stylized game rock, simple shapes", (3, 2.4, 3), 450),
    "RockB": ("a broken flat slab of stone with sharp chipped edges, stylized game rock, simple shapes", (4, 1.8, 3), 450),
    "RockC": ("a sharp pointed wedge shaped shard of stone, stylized game rock, simple shapes", (2.4, 3, 2.4), 450),
    "CrystalShard": ("a single tall faceted gemstone crystal pointing up, stylized game asset, simple shapes", (1.6, 4, 1.6), 450),
    # crystal / magma cores
    "CoreCrystalCyan": ("a geode cluster of glowing cyan and magenta crystal points, stylized game asset", (4.5, 5, 4.5), 4000),
    "CoreQuartz": ("a tall cluster of translucent white lavender quartz crystal spires, stylized game asset", (4, 9, 4), 4000),
    "CoreAmethyst": ("a cluster of deep violet amethyst crystals pointing upward, stylized game asset", (5, 5, 5), 4000),
    "CoreMagma": ("a lump of cracked black rock with glowing orange lava seams, stylized game asset", (4.5, 4.5, 4.5), 3500),
    "CoreObsidian": ("a jagged cluster of black volcanic glass shards with violet inner glow, stylized game asset", (5, 6, 5), 4000),
    # arm gauntlets (forearm + knuckle block; one per arm family)
    "ArmStarter": ("a taped leather wrapped boxing glove with a bandaged wrist, simple, stylized game asset", (2.2, 2.2, 3.4), 3000),
    "ArmStonebreaker": ("a massive armored gauntlet glove made of stacked stone slabs with large blocky knuckle plates, stylized game asset", (3.2, 3.2, 4.8), 5000),
    "ArmAlloy": ("an industrial mechanical armored gauntlet with steel plating, hydraulic pistons and yellow and black hazard stripes, stylized game asset", (3, 3, 5), 6000),
    "ArmCrystal": ("an armored gauntlet glove of white plating with faceted cyan crystal shards growing out of it, stylized game asset", (3.2, 3.2, 5), 6000),
    "ArmMagma": ("a black basalt armored gauntlet glove with glowing orange lava cracks and spiked fins, stylized game asset", (3.4, 3.4, 5), 6000),
    "ArmVoid": ("a dark armored gauntlet glove of black metal with violet starlight inlays and sharp fins, stylized game asset", (3.2, 3.2, 5), 6000),
    # hero landmarks
    "ForgeHero": ("a giant industrial forge machine with an anvil, glowing furnace, robotic press arms and chimneys, stylized game landmark", (28, 22, 28), 18000),
    "HaloGate": ("a gigantic ring shaped metallic gate with a glowing orange inner ring, stylized game landmark", (30, 30, 6), 10000),
    "CrystalArch": ("a giant natural arch of translucent blue and purple crystals, stylized game landmark", (34, 26, 12), 14000),
    "EmberFang": ("a towering black volcanic fang spire rock with glowing lava cracks, stylized game landmark", (22, 40, 22), 14000),
    "Pedestal": ("a sci-fi display pedestal with a glowing ring and a metallic base, stylized game asset", (6, 3, 6), 4000),
}

# Studio inserts the finished model into Workspace; claim the newest unclaimed one.
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
local out = {}
for _, d in found:GetDescendants() do
	if d:IsA("MeshPart") then
		table.insert(out, {mesh = d.MeshId, tex = d.TextureID, size = {d.Size.X, d.Size.Y, d.Size.Z}, path = d:GetFullName()})
	end
end
return game:GetService("HttpService"):JSONEncode(out)
"""


def main():
    state = {}
    if os.path.exists(STATE):
        state = json.load(open(STATE, encoding="utf-8"))
    wanted = sys.argv[1:] or [n for n in PROMPTS if state.get(n, {}).get("status") != "Completed"]
    client = studio_mcp.Client()
    for name in wanted:
        prompt, size, tris = PROMPTS[name]
        args = {
            "textPrompt": prompt,
            "size": {"x": size[0], "y": size[1], "z": size[2]},
            "maxTriangles": tris,
            "segmentation": "none",
        }
        try:
            result = client.call("generate_mesh", args, 900).get("result", {})
        except TimeoutError:
            state[name] = {"prompt": prompt, "status": "Timeout"}
            print(name, "timeout")
            continue
        entry = {"prompt": prompt}
        if result.get("isError"):
            entry["status"] = "Failed"
            entry["error"] = (result.get("content") or [{}])[0].get("text", "")
            print(name, "FAILED", entry["error"])
        else:
            entry["status"] = "Completed"
            structured = result.get("structuredContent") or {}
            entry["publishedAssetId"] = structured.get("publishedAssetId")
            res = client.call("execute_luau", {"code": CLAIM % name, "datamodel_type": "Edit"}, 120).get("result", {})
            try:
                parts = json.loads(res["content"][0]["text"])
            except Exception:
                parts = []
            if parts:
                entry["meshId"] = parts[0]["mesh"]
                entry["textureId"] = parts[0]["tex"]
                entry["size"] = parts[0]["size"]
                entry["parts"] = len(parts)
            print(name, "OK", entry.get("publishedAssetId"), entry.get("meshId"))
        state[name] = entry
        json.dump(state, open(STATE, "w", encoding="utf-8"), indent=1)


if __name__ == "__main__":
    main()
