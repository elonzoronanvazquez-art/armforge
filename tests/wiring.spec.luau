-- Static wiring checks: scans the source tree so a renamed remote, a missing handler or an unregistered panel is caught
-- by the test run instead of by a player. (Pure text analysis: no Roblox runtime needed.)
local fs = require("@lune/fs")

local function walk(dir: string, out: { string })
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			walk(path, out)
		elseif name:match("%.luau$") then
			table.insert(out, path)
		end
	end
end

local function read(path: string): string
	return fs.readFile(path)
end

local function files(dir: string): { string }
	local out = {}
	walk(dir, out)
	return out
end

local function setOf(list: { string }): { [string]: boolean }
	local s = {}
	for _, v in list do
		s[v] = true
	end
	return s
end

-- every capture of `pattern` in every file under dir
local function captures(dir: string, pattern: string): { [string]: string }
	local found = {}
	for _, path in files(dir) do
		for hit in read(path):gmatch(pattern) do
			found[hit] = path
		end
	end
	return found
end

return function(t, u)
	local Net = u:load("Net")
	local Assets = u:load("Config/Assets")
	local Rocks = u:load("Config/Rocks")
	local Arms = u:load("Config/Arms")
	local Skills = u:load("Config/Skills")
	local Designs = u:load("Runtime/ArmDesigns")

	t.test("every remote used in the code exists in Net", function()
		local known = setOf(Net.Events)
		for _, name in Net.Functions do
			known[name] = true
		end
		for _, dir in { "src/server", "src/client" } do
			for name, path in captures(dir, "remotes%.(%w+)") do
				t.truthy(known[name], `remotes.{name} in {path} is not defined in Net`)
			end
		end
		for name, path in captures("src/client", "Remotes%.(%w+)") do
			t.truthy(known[name], `Remotes.{name} in {path} is not defined in Net`)
		end
	end)

	t.test("every effect kind the server sends has a client handler", function()
		-- fxNear(pos, "Kind", ...)
		local kinds = {}
		for _, path in files("src/server") do
			for kind in read(path):gmatch('fxNear%([^,]+,%s*"(%w+)"') do
				kinds[kind] = path
			end
		end
		local client = read("src/client/Controllers/EffectsController.luau")
		local dispatch = client:match("local dispatch[^=]*= (%b{})")
		t.truthy(dispatch, "found the Fx dispatch table")
		local count = 0
		for kind, path in kinds do
			count += 1
			t.truthy(dispatch:find(kind .. " = ", 1, true), `Fx kind "{kind}" sent from {path} has no client handler`)
		end
		t.truthy(count >= 8, "found the server's fx kinds")
	end)

	t.test("every notification kind the server sends has a client handler", function()
		local kinds = {}
		for _, path in files("src/server") do
			for kind in read(path):gmatch('notify%([^,]+,%s*"(%w+)"') do
				kinds[kind] = path
			end
		end
		local client = read("src/client/UI/Notifications.luau")
		local count = 0
		for kind, path in kinds do
			count += 1
			t.truthy(client:find(`kind == "{kind}"`, 1, true), `Notify kind "{kind}" from {path} has no handler`)
		end
		t.truthy(count >= 4)
	end)

	t.test("every UI request action exists on the server", function()
		local server = read("src/server/Services/Requests.luau")
		local count = 0
		for action, path in captures("src/client", 'Store%.request%("(%w+)"') do
			count += 1
			t.truthy(server:find("\t" .. action .. " = function", 1, true), `Request "{action}" used in {path} has no server handler`)
		end
		for action, path in captures("src/client", 'InvokeServer%("(%w+)"') do
			count += 1
			t.truthy(server:find("\t" .. action .. " = function", 1, true), `Request "{action}" used in {path} has no server handler`)
		end
		t.truthy(count >= 8)
	end)

	t.test("every registered panel exists and exports the panel interface", function()
		local registry = read("src/client/UI/Panels.luau")
		local list = registry:match("for _, name in (%b{}) do")
		t.truthy(list)
		local n = 0
		for name in list:gmatch('"(%w+)"') do
			n += 1
			local path = `src/client/UI/{name}.luau`
			t.truthy(fs.isFile(path), path .. " exists")
			local src = read(path)
			for _, member in { "Panel.name", "Panel.title", "Panel.size", "Panel.build", "Panel.refresh" } do
				t.truthy(src:find(member, 1, true), `{name} defines {member}`)
			end
		end
		t.eq(n, 7, "seven panels")
	end)

	t.test("every prompt panel name used by the world is a registered panel", function()
		local registry = read("src/client/UI/Panels.luau")
		for _, path in files("src/server/World") do
			for panel in read(path):gmatch('Build%.prompt%([^%)]-"(%w+)",%s*[%d%.]+,') do
				_ = panel
			end
			for panel in read(path):gmatch('Build%.prompt%([^"]*"[^"]*",%s*"[^"]*",%s*"(%w+)"') do
				t.truthy(registry:find(panel .. "Panel", 1, true), `prompt opens unknown panel "{panel}" ({path})`)
			end
		end
	end)

	t.test("every sound key used by the client exists in the asset registry", function()
		local count = 0
		for key, path in captures("src/client", 'sound%("(%w+)"') do
			count += 1
			t.truthy(Assets.Sounds[key], `sound "{key}" used in {path} is not registered`)
		end
		t.truthy(count >= 7, `found {count} sound keys`)
		for _, rock in Rocks.Defs do
			t.truthy(Assets.Sounds["Hit" .. rock.sound], `Hit{rock.sound} sound for {rock.id}`)
			t.truthy(Assets.Sounds["Break" .. rock.sound], `Break{rock.sound} sound for {rock.id}`)
		end
		for key, list in Assets.Sounds do
			for _, s in list do
				t.truthy(s.id:match("^rbxassetid://%d+$"), key .. " has a real asset id")
				t.truthy(s.volume > 0 and s.volume <= 1.2)
			end
		end
	end)

	t.test("registered meshes have real ids", function()
		local n = 0
		for key, m in Assets.Meshes do
			n += 1
			t.truthy(m.mesh:match("^rbxassetid://%d+$"), key .. " mesh id")
			if m.texture then
				t.truthy(m.texture:match("^rbxassetid://%d+$"), key .. " texture id")
			end
		end
		t.truthy(n >= 20)
	end)

	t.test("every arm has a visual design, an effect entry and registered meshes", function()
		for _, id in Arms.Order do
			local design = Designs.Designs[id]
			t.truthy(design and #design >= 6, id .. " design")
			t.truthy(Designs.Effects[id] ~= nil, id .. " effects entry")
			local base, tiers = 0, {}
			for _, p in design do
				t.truthy(p.limb == "UpperArm" or p.limb == "LowerArm" or p.limb == "Hand", id .. " limb")
				if p.mesh then
					t.truthy(Assets.Meshes[p.mesh], `{id} mesh {p.mesh} is registered`)
				end
				if (p.tier or 0) == 0 then
					base += 1
				else
					tiers[p.tier] = true
				end
			end
			t.truthy(base >= 4, id .. " has base pieces")
			t.truthy(tiers[1] and tiers[2] and tiers[3], id .. " gains pieces at every upgrade tier")
		end
	end)

	t.test("skills have a hotkey slot and animation", function()
		local Anim = u:load("Config/Animations")
		local slots = {}
		for _, id in Skills.Order do
			slots[Skills.Defs[id].key] = true
			t.truthy(Anim.SkillMoves[id], id .. " has a move")
		end
		t.truthy(slots[1] and slots[2] and slots[3] and slots[4])
	end)

	t.test("all source files are strict-typed", function()
		local lax = {}
		for _, dir in { "src/shared", "src/server", "src/client" } do
			for _, path in files(dir) do
				if not read(path):match("^%-%-!strict") then
					table.insert(lax, path)
				end
			end
		end
		t.deepEq(lax, {})
	end)

	t.test("dev tooling is gated to Studio", function()
		local dev = read("src/server/Dev/DevTools.luau")
		t.truthy(dev:find("RunService:IsStudio()", 1, true), "DevTools checks IsStudio")
		t.truthy(dev:find("if not enabled then", 1, true), "bridge only created when enabled")
		local cam = read("src/client/Controllers/DevCamController.luau")
		t.truthy(cam:find("IsStudio", 1, true))
		local progress = read("src/server/Services/ProgressService.luau")
		t.truthy(progress:find("IsStudio", 1, true), "the dev progression multiplier is Studio-only")
		-- nothing outside Dev/ may reference the dev bridge
		for _, path in files("src") do
			if not path:find("Dev", 1, true) then
				t.eq(read(path):find("ArmforgeDev", 1, true), nil, path .. " must not touch the dev bridge")
			end
		end
	end)

	t.test("no source file contains placeholder asset ids", function()
		for _, path in files("src") do
			local src = read(path)
			t.eq(src:find("rbxassetid://0", 1, true), nil, path)
			t.eq(src:find("rbxassetid://12345", 1, true), nil, path)
		end
	end)

	t.test("creature bodies: every archetype has a template, every mesh is registered, every animated joint exists", function()
		local Creatures = u:load("Config/Creatures")
		local builder = read("src/server/World/CreatureBuilder.luau")
		for id, def in Creatures.Defs do
			t.truthy(builder:find(def.archetype .. " = " .. def.archetype, 1, true), `{id}: no template for archetype {def.archetype}`)
			if def.visual.mesh then
				t.truthy(Assets.Meshes[def.visual.mesh], `{id}: visual.mesh {def.visual.mesh} is not in Config/Assets`)
			end
		end
		-- the client animates joints by name (J_<Part>); each name it drives must be created by some template
		local controller = read("src/client/Controllers/CreatureController.luau")
		local joints = 0
		for name in controller:gmatch('setJoint%(rig, "(%w+)"') do
			joints += 1
			local built = builder:find(`"{name}"`, 1, true) ~= nil
				or (name:match("^Arm[LR]$") ~= nil and builder:find('"Arm" .. n', 1, true) ~= nil)
				or (name:match("^Leg[LR]$") ~= nil and builder:find('"Leg" .. n', 1, true) ~= nil)
			t.truthy(built, `joint {name} is animated but never built`)
		end
		t.truthy(joints >= 8, "found the animated joints")
	end)

	t.test("creature fx and notification kinds are all handled, and the creature remotes accept nothing from clients", function()
		local service = read("src/server/Services/EncounterService.luau")
		-- the only client -> server inputs are the existing Punch / Skill / Request remotes: there is no creature remote
		t.eq(service:find("OnServerEvent", 1, true), nil, "EncounterService listens to no remote")
		t.eq(service:find("OnServerInvoke", 1, true), nil)
		for _, name in Net.Events do
			t.eq(name:lower():find("creature", 1, true), nil, name)
		end
		for _, name in Net.Functions do
			t.eq(name:lower():find("creature", 1, true), nil, name)
		end
	end)
end
