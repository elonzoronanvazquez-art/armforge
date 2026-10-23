-- Loads the pure modules under src/shared inside Lune while emulating the tiny slice of the Roblox Instance API they
-- use (`script`, `script.Parent`, child lookup by name, `require(node)`), plus the Roblox datatypes (Vector3, CFrame,
-- Color3, Enum...) from @lune/roblox. The exact same source files therefore run in Roblox and in the tests.
-- Must be run from the repository root.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Loader = {}

local data = setmetatable({}, { __mode = "k" })

local function newNode(name, parent, path, universe)
	local node = {}
	data[node] = { name = name, parent = parent, children = {}, path = path, loaded = false, value = nil, universe = universe }
	setmetatable(node, {
		__index = function(self, key)
			local d = data[self]
			if key == "Name" then
				return d.name
			elseif key == "Parent" then
				return d.parent
			elseif key == "FindFirstChild" or key == "WaitForChild" then
				return function(_, childName)
					return d.children[childName]
				end
			end
			local child = d.children[key]
			if child == nil then
				error(`'{key}' is not a valid member of '{d.name}'`, 2)
			end
			return child
		end,
		__newindex = function()
			error("virtual instance is read-only")
		end,
		__tostring = function(self)
			return data[self].name
		end,
	})
	return node
end

local function scan(path, node, universe)
	for _, entry in fs.readDir(path) do
		local full = path .. "/" .. entry
		if fs.isDir(full) then
			local child = newNode(entry, node, nil, universe)
			data[node].children[entry] = child
			scan(full, child, universe)
		elseif entry:match("%.luau$") and not entry:match("%.spec%.luau$") then
			local name = entry:gsub("%.luau$", "")
			data[node].children[name] = newNode(name, node, full, universe)
		end
	end
end

local datatypes = {
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	Enum = roblox.Enum,
	UDim2 = roblox.UDim2,
	UDim = roblox.UDim,
	NumberRange = roblox.NumberRange,
	NumberSequence = roblox.NumberSequence,
	ColorSequence = roblox.ColorSequence,
	Instance = roblox.Instance,
}

-- Minimal stand-ins so modules that call game:GetService / task.* at load time can be required in tests.
-- (Anything that actually USES a service at call time is runtime glue and is exercised in Studio, not here.)
local stubs = {
	game = {
		GetService = function(_, name)
			return {
				Name = name,
				IsServer = function()
					return true
				end,
				IsStudio = function()
					return false
				end,
			}
		end,
	},
	task = {
		spawn = function(fn, ...)
			fn(...)
		end,
		defer = function(fn, ...)
			fn(...)
		end,
		delay = function(_, fn, ...)
			fn(...)
		end,
		wait = function()
			return 0
		end,
	},
}

local function requireNode(node)
	local d = data[node]
	if d == nil or d.path == nil then
		error("require: not a module: " .. tostring(node), 2)
	end
	if d.loading then
		error("require: cyclic dependency at " .. d.path, 2)
	end
	if d.loaded then
		return d.value
	end
	d.loading = true
	local env = { script = node, require = requireNode }
	for k, v in datatypes do
		env[k] = v
	end
	for k, v in stubs do
		env[k] = v
	end
	-- a universe may override any global (the server harness swaps in a fake Roblox world)
	for k, v in d.universe.env do
		env[k] = v
	end
	setmetatable(env, { __index = _G })
	local chunk = luau.load(fs.readFile(d.path), { debugName = d.path, environment = env })
	d.value = chunk()
	d.loaded = true
	d.loading = false
	return d.value
end

-- Returns a fresh module universe (so tests can't leak state between runs).
--   opts.server   also scan src/server (load with universe:loadServer("Services/RockService"))
--   opts.env      function(sharedRoot) -> table of globals that replace the stubs (game, task, os, Instance...)
--   opts.replace  { ["Runtime/ArmBuilder"] = module, ["server:World/RockBuilder"] = module } returned instead of the real file
function Loader.new(opts)
	opts = opts or {}
	local universe = { env = {} }
	local root = newNode("Armforge", nil, nil, universe)
	scan("src/shared", root, universe)
	local serverRoot = nil
	if opts.server then
		serverRoot = newNode("Server", nil, nil, universe)
		scan("src/server", serverRoot, universe)
	end
	if opts.env then
		universe.env = opts.env(root)
	end
	local function resolve(path)
		local node = root
		if path:sub(1, 7) == "server:" then
			node = assert(serverRoot, "universe has no server tree")
			path = path:sub(8)
		end
		for segment in path:gmatch("[^/]+") do
			node = node:FindFirstChild(segment)
			assert(node ~= nil, "no such module: " .. path)
		end
		return node
	end
	for path, value in opts.replace or {} do
		local d = data[resolve(path)]
		d.loaded = true
		d.value = value
	end
	-- universe:load("Logic/Formulas")
	function universe.load(_, path)
		return requireNode(resolve(path))
	end
	function universe.loadServer(_, path)
		return requireNode(resolve("server:" .. path))
	end
	-- Deep-copies a config table so a test can change numbers without leaking.
	function universe.clone(_, value)
		local function copy(v)
			if type(v) ~= "table" then
				return v
			end
			local out = {}
			for k, x in v do
				out[k] = copy(x)
			end
			return out
		end
		return copy(value)
	end
	return universe
end

return Loader
