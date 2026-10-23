"""Push the Rojo project's scripts into the OPEN Studio edit DataModel through the MCP execute_luau tool.

This is a fast hot-reload loop that does not need the Rojo Studio plugin: edit files, run this, then start a playtest.
It mirrors default.project.json for the three script roots (shared, server, client). `*.server.luau` becomes a Script,
`*.client.luau` a LocalScript, other `*.luau` a ModuleScript; folders become Folders. Unchanged files are skipped
(hash cache in build/sync_cache.json). Usage:  python scripts/studio_sync.py [--all]
"""
import hashlib
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import studio_mcp

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CACHE = os.path.join(ROOT, "build", "sync_cache.json")

# (local dir, Studio path of the container that holds it as a Folder named "Armforge")
MAPPINGS = [
    ("src/shared", ["ReplicatedStorage"], "Armforge"),
    ("src/server", ["ServerScriptService"], "Armforge"),
    ("src/client", ["StarterPlayer", "StarterPlayerScripts"], "Armforge"),
]

LUAU_HEAD = r"""
local function resolve(path)
	local node = game
	for _, name in path do
		node = node:FindFirstChild(name) or error("missing service " .. name)
	end
	return node
end
local function ensure(parent, name, class)
	local child = parent:FindFirstChild(name)
	if child and child.ClassName ~= class then
		child:Destroy()
		child = nil
	end
	if not child then
		child = Instance.new(class)
		child.Name = name
		child.Parent = parent
	end
	return child
end
local function put(rootPath, rootName, segments, class, source)
	local node = ensure(resolve(rootPath), rootName, "Folder")
	for i = 1, #segments - 1 do
		node = ensure(node, segments[i], "Folder")
	end
	local script = ensure(node, segments[#segments], class)
	script.Source = source
end
local function remove(rootPath, rootName, segments)
	local node = resolve(rootPath):FindFirstChild(rootName)
	for i = 1, #segments do
		if not node then return end
		node = node:FindFirstChild(segments[i])
	end
	if node then node:Destroy() end
end
"""


def long_string(text):
    level = 0
    while True:
        eq = "=" * level
        if f"]{eq}]" not in text:
            return f"[{eq}[\n{text}]{eq}]"
        level += 1


def class_and_name(filename):
    if filename.endswith(".server.luau"):
        return "Script", filename[: -len(".server.luau")]
    if filename.endswith(".client.luau"):
        return "LocalScript", filename[: -len(".client.luau")]
    return "ModuleScript", filename[: -len(".luau")]


def collect():
    items = {}
    for local, path, root_name in MAPPINGS:
        base = os.path.join(ROOT, local)
        for dirpath, _dirs, files in os.walk(base):
            for f in files:
                if not f.endswith(".luau") or f.endswith(".spec.luau"):
                    continue
                rel = os.path.relpath(os.path.join(dirpath, f), base)
                parts = rel.split(os.sep)
                cls, name = class_and_name(parts[-1])
                segments = parts[:-1] + [name]
                text = open(os.path.join(dirpath, f), encoding="utf-8").read()
                key = local + "/" + "/".join(segments)
                items[key] = {"path": path, "root": root_name, "segments": segments, "class": cls, "source": text}
    return items


def main():
    force = "--all" in sys.argv
    cache = {}
    if os.path.exists(CACHE) and not force:
        cache = json.load(open(CACHE))
    items = collect()
    new_cache = {}
    batches, current, size = [], [], 0
    for key, item in items.items():
        digest = hashlib.sha1(item["source"].encode("utf-8")).hexdigest()
        new_cache[key] = {"hash": digest, **{k: item[k] for k in ("path", "root", "segments")}}
        if cache.get(key, {}).get("hash") == digest:
            continue
        line = "put({%s}, %s, {%s}, %s, %s)\n" % (
            ", ".join(json.dumps(p) for p in item["path"]),
            json.dumps(item["root"]),
            ", ".join(json.dumps(s) for s in item["segments"]),
            json.dumps(item["class"]),
            long_string(item["source"]),
        )
        if size + len(line) > 120_000 and current:
            batches.append(current)
            current, size = [], 0
        current.append(line)
        size += len(line)
    removed = [k for k in cache if k not in new_cache]
    if current:
        batches.append(current)
    if not batches and not removed:
        print("nothing to sync")
        return
    client = studio_mcp.Client()
    count = 0
    for batch in batches:
        code = LUAU_HEAD + "".join(batch) + "return 'ok'"
        result = client.call("execute_luau", {"code": code, "datamodel_type": "Edit"}, 300).get("result", {})
        text = result.get("content", [{}])[0].get("text", "")
        if text.strip() != "ok":
            print("sync error:", text[:500])
            sys.exit(1)
        count += len(batch)
    if removed:
        code = LUAU_HEAD
        for key in removed:
            info = cache[key]
            code += "remove({%s}, %s, {%s})\n" % (
                ", ".join(json.dumps(p) for p in info["path"]),
                json.dumps(info["root"]),
                ", ".join(json.dumps(s) for s in info["segments"]),
            )
        code += "return 'ok'"
        client.call("execute_luau", {"code": code, "datamodel_type": "Edit"}, 300)
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    json.dump(new_cache, open(CACHE, "w"))
    print(f"synced {count} files, removed {len(removed)}")


if __name__ == "__main__":
    main()
