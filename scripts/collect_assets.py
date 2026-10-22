"""Wait for the queued AI generation jobs (scripts/gen_assets.py) and record the resulting real asset ids.

Reads docs/generated_assets.json, waits for every job, then asks Studio for the MeshParts that were inserted into
Workspace (their MeshId / TextureID / Size are the real uploaded asset ids) and matches them to the prompt names.
Writes the result back to docs/generated_assets.json.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import studio_mcp

STATE = os.path.join(os.path.dirname(__file__), "..", "docs", "generated_assets.json")

LUAU = """
local out = {}
for _, child in workspace:GetChildren() do
	if child:IsA("Model") then
		for _, d in child:GetDescendants() do
			if d:IsA("MeshPart") then
				table.insert(out, {name = child.Name, mesh = d.MeshId, tex = d.TextureID, size = {d.Size.X, d.Size.Y, d.Size.Z}, path = d:GetFullName()})
			end
		end
	end
end
return game:GetService("HttpService"):JSONEncode(out)
"""


def main():
    state = json.load(open(STATE, encoding="utf-8"))
    client = studio_mcp.Client()
    for name, entry in state.items():
        if entry.get("status") in ("Completed", "Failed", "Moderated") and entry.get("done"):
            continue
        result = client.call("wait_job_finished", {"jobId": entry["jobId"], "timeout": 600}, 700).get("result", {})
        text = result["content"][0]["text"] if result.get("content") else "{}"
        info = json.loads(text)
        entry["status"] = info.get("status", "?")
        job = info.get("jobResult", {})
        structured = job.get("structuredContent") or {}
        if structured.get("publishedAssetId"):
            entry["publishedAssetId"] = structured["publishedAssetId"]
        if info.get("status") == "Failed":
            entry["error"] = (job.get("content") or [{}])[0].get("text", "")
        entry["done"] = True
        print(name, entry["status"], entry.get("publishedAssetId", entry.get("error", "")))
    res = client.call("execute_luau", {"code": LUAU, "datamodel_type": "Edit"}, 300).get("result", {})
    parts = json.loads(res["content"][0]["text"])
    for name, entry in state.items():
        prompt = entry["prompt"]
        for p in parts:
            if prompt.startswith(p["name"][:60]) or p["name"].startswith(prompt[:60]):
                entry["meshId"] = p["mesh"]
                entry["textureId"] = p["tex"]
                entry["size"] = p["size"]
                entry["instance"] = p["path"]
    json.dump(state, open(STATE, "w", encoding="utf-8"), indent=1)
    for name, entry in state.items():
        print(name, entry.get("status"), entry.get("meshId"), entry.get("textureId"))


if __name__ == "__main__":
    main()
