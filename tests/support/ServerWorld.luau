-- A deterministic fake Roblox server for exercising src/server services under Lune.
--
--   * virtual clock + scheduler: task.wait / delay / spawn / defer and os.clock / os.time run on `world.sched`, so tests
--     advance time explicitly (world:advance(seconds)) and concurrency (a save racing a leave, a respawn racing a
--     player) is exactly reproducible.
--   * lightweight Instance tree (Parent/Children/Attributes/Tags/Destroy) and the services the server touches:
--     Players, CollectionService, ReplicatedStorage, RunService, DataStoreService (with latency and failure injection).
--   * the real shared Config/Logic/Net modules and the real server services; only the mesh/part builders
--     (RockBuilder, ArmBuilder) are replaced by recording stubs.
--
-- This verifies service glue and state transitions. It is NOT a substitute for Studio / live DataStore verification;
-- docs/PERSISTENCE_TEST.md separates the two.

local roblox = require("@lune/roblox")
local Loader = require("./Loader")

local ServerWorld = {}

local EPOCH = 1700000000

-- Signals ------------------------------------------------------------------------------------------------------

local function newSignal(world)
	local handlers = {}
	local signal = {}
	function signal.Connect(_, fn)
		local conn = { Connected = true }
		table.insert(handlers, { conn = conn, fn = fn })
		function conn.Disconnect()
			conn.Connected = false
		end
		return conn
	end
	function signal.Fire(_, ...)
		for _, h in table.clone(handlers) do
			if h.conn.Connected then
				world.sched.spawn(h.fn, ...)
			end
		end
	end
	return signal
end

-- Scheduler ----------------------------------------------------------------------------------------------------

local function newScheduler()
	local s = { now = 0, seq = 0, queue = {}, errors = {} }

	local function resume(co, ...)
		local ok, err = coroutine.resume(co, ...)
		if not ok then
			table.insert(s.errors, tostring(err))
		end
	end

	local function push(t, item)
		s.seq += 1
		item.t = t
		item.seq = s.seq
		table.insert(s.queue, item)
	end

	local function pop(limit)
		local best, bestIndex = nil, nil
		for i, item in s.queue do
			if item.t <= limit and (best == nil or item.t < best.t or (item.t == best.t and item.seq < best.seq)) then
				best, bestIndex = item, i
			end
		end
		if best then
			table.remove(s.queue, bestIndex)
		end
		return best
	end

	function s.spawn(fn, ...)
		local co = if type(fn) == "thread" then fn else coroutine.create(fn)
		resume(co, ...)
		return co
	end

	function s.defer(fn, ...)
		push(s.now, { fn = fn, args = table.pack(...) })
	end

	function s.delay(seconds, fn, ...)
		push(s.now + (seconds or 0), { fn = fn, args = table.pack(...) })
	end

	function s.wait(seconds)
		seconds = seconds or 0.03
		assert(coroutine.isyieldable(), "task.wait outside a scheduler thread: wrap the call in world:run(...)")
		push(s.now + seconds, { co = coroutine.running() })
		coroutine.yield()
		return seconds
	end

	function s.advance(dt)
		local target = s.now + dt
		while true do
			local item = pop(target)
			if not item then
				break
			end
			s.now = math.max(s.now, item.t)
			if item.co then
				resume(item.co)
			else
				resume(coroutine.create(item.fn), table.unpack(item.args, 1, item.args.n))
			end
		end
		s.now = target
	end

	return s
end

-- Instances ----------------------------------------------------------------------------------------------------

local BASEPARTS = { Part = true, MeshPart = true, WedgePart = true, SpawnLocation = true }

local function isA(class, query)
	return class == query or query == "Instance" or (query == "BasePart" and BASEPARTS[class] == true)
end

function ServerWorld.new(opts)
	opts = opts or {}
	local world = {
		sched = newScheduler(),
		fired = {}, -- every RemoteEvent:FireClient: { remote, player, args }
		warnings = {},
		stores = {},
		closeCallbacks = {},
		kicked = {},
		armAttachments = {},
		rockBuilds = {},
		studio = opts.studio == true,
		jobId = opts.jobId or "job-A",
		sharedStores = opts.sharedStores, -- lets two worlds ("servers") share the same DataStores
	}
	local sched = world.sched
	local state = setmetatable({}, { __mode = "k" })
	local tagged = {} -- tag -> { node, ... }
	local classInit = {}
	local methods = {}

	local function reparent(node, parent)
		local st = state[node]
		if st.parent then
			local siblings = state[st.parent].children
			table.remove(siblings, table.find(siblings, node))
		end
		st.parent = parent
		if parent then
			table.insert(state[parent].children, node)
		end
	end

	local nodeMeta = {}
	function nodeMeta.__index(self, key)
		local st = state[self]
		local v = st.props[key]
		if v ~= nil then
			return v
		end
		if key == "Parent" then
			return st.parent
		elseif key == "ClassName" then
			return st.class
		end
		local m = methods[key]
		if m then
			return m
		end
		for _, child in st.children do
			if state[child].props.Name == key then
				return child
			end
		end
		return nil
	end
	function nodeMeta.__newindex(self, key, value)
		local st = state[self]
		if key == "Parent" then
			reparent(self, value)
		elseif key == "ClassName" then
			error("ClassName is read-only")
		else
			st.props[key] = value
			if BASEPARTS[st.class] then
				if key == "CFrame" then
					st.props.Position = value.Position
				elseif key == "Position" then
					st.props.CFrame = roblox.CFrame.new(value)
				end
			end
		end
	end
	function nodeMeta.__tostring(self)
		return `{state[self].class}({state[self].props.Name})`
	end

	local function newNode(class, props)
		local node = {}
		state[node] = { class = class, props = props or {}, parent = nil, children = {}, attrs = {}, tags = {}, destroyed = false }
		state[node].props.Name = state[node].props.Name or class
		setmetatable(node, nodeMeta)
		if classInit[class] then
			classInit[class](node, state[node].props)
		end
		return node
	end
	local make = newNode
	world.newNode = newNode

	function methods.IsA(self, query)
		return isA(state[self].class, query)
	end
	function methods.GetChildren(self)
		return table.clone(state[self].children)
	end
	local function descendants(node, out)
		for _, child in state[node].children do
			table.insert(out, child)
			descendants(child, out)
		end
		return out
	end
	function methods.GetDescendants(self)
		return descendants(self, {})
	end
	function methods.FindFirstChild(self, name, recursive)
		local list = if recursive then descendants(self, {}) else state[self].children
		for _, child in list do
			if state[child].props.Name == name then
				return child
			end
		end
		return nil
	end
	methods.WaitForChild = methods.FindFirstChild
	function methods.FindFirstChildOfClass(self, class)
		for _, child in state[self].children do
			if state[child].class == class then
				return child
			end
		end
		return nil
	end
	function methods.FindFirstChildWhichIsA(self, class)
		for _, child in state[self].children do
			if isA(state[child].class, class) then
				return child
			end
		end
		return nil
	end
	function methods.IsDescendantOf(self, ancestor)
		local p = state[self].parent
		while p do
			if p == ancestor then
				return true
			end
			p = state[p].parent
		end
		return false
	end
	function methods.SetAttribute(self, name, value)
		state[self].attrs[name] = value
	end
	function methods.GetAttribute(self, name)
		return state[self].attrs[name]
	end
	function methods.Destroy(self)
		local st = state[self]
		for _, child in table.clone(st.children) do
			methods.Destroy(child)
		end
		st.destroyed = true
		for tag in st.tags do
			local list = tagged[tag]
			local i = list and table.find(list, self)
			if i then
				table.remove(list, i)
			end
		end
		reparent(self, nil)
	end
	function methods.ClearAllChildren(self)
		for _, child in table.clone(state[self].children) do
			methods.Destroy(child)
		end
	end
	function methods.GetPivot(self)
		return state[self].props.CFrame or roblox.CFrame.new(state[self].props.Position or roblox.Vector3.zero)
	end
	function world.isDestroyed(node)
		return state[node].destroyed
	end

	-- Classes -------------------------------------------------------------------------------------------------
	classInit.RemoteEvent = function(node, props)
		props.OnServerEvent = newSignal(world)
		props.FireClient = function(_, player, ...)
			table.insert(world.fired, { remote = props.Name, player = player, args = table.pack(...) })
		end
		props.FireAllClients = function(_, ...)
			table.insert(world.fired, { remote = props.Name, args = table.pack(...) })
		end
	end
	classInit.Humanoid = function(_, props)
		props.Health = 100
		props.MaxHealth = 100
		props.Died = newSignal(world)
	end
	classInit.IntValue = function(_, props)
		props.Value = 0
	end
	classInit.Part = function(_, props)
		props.Position = roblox.Vector3.zero
		props.CFrame = roblox.CFrame.new(roblox.Vector3.zero)
	end

	-- Services ------------------------------------------------------------------------------------------------
	local Players = make("Folder", { Name = "Players", CharacterAutoLoads = true, RespawnTime = 5 })
	local playersState = state[Players].props
	playersState.PlayerAdded = newSignal(world)
	playersState.PlayerRemoving = newSignal(world)
	local playerList = {}
	playersState.GetPlayers = function()
		return table.clone(playerList)
	end
	playersState.GetPlayerByUserId = function(_, userId)
		for _, p in playerList do
			if p.UserId == userId then
				return p
			end
		end
		return nil
	end

	local workspaceNode = make("Folder", { Name = "Workspace" })
	state[workspaceNode].props.Terrain = make("Folder", { Name = "Terrain" })
	state[workspaceNode].props.GetServerTimeNow = function()
		return EPOCH + sched.now
	end
	state[workspaceNode].props.Raycast = function()
		return nil
	end
	world.workspace = workspaceNode

	local Shared -- set by the loader env
	local ReplicatedStorage = make("Folder", { Name = "ReplicatedStorage" })
	state[ReplicatedStorage].props.WaitForChild = function(_, name)
		if name == "Armforge" then
			return Shared
		end
		return methods.FindFirstChild(ReplicatedStorage, name)
	end

	local RunService = make("Folder", { Name = "RunService" })
	state[RunService].props.IsServer = function()
		return true
	end
	state[RunService].props.IsStudio = function()
		return world.studio
	end
	state[RunService].props.Heartbeat = newSignal(world)

	local CollectionService = make("Folder", { Name = "CollectionService" })
	state[CollectionService].props.AddTag = function(_, node, tag)
		if not state[node].tags[tag] then
			state[node].tags[tag] = true
			tagged[tag] = tagged[tag] or {}
			table.insert(tagged[tag], node)
		end
	end
	state[CollectionService].props.RemoveTag = function(_, node, tag)
		if state[node].tags[tag] then
			state[node].tags[tag] = nil
			table.remove(tagged[tag], table.find(tagged[tag], node))
		end
	end
	state[CollectionService].props.GetTagged = function(_, tag)
		return table.clone(tagged[tag] or {})
	end

	-- DataStore with latency (virtual seconds) and failure injection
	local function deepCopy(v)
		return world.universe:load("Logic/Persistence").deepCopy(v)
	end
	local function newStore(name)
		local store = { name = name, data = {}, calls = {}, latency = 0, failNext = 0, failAll = opts.storeFailAll == true, commits = 0 }
		local function begin(op, key)
			table.insert(store.calls, { op = op, key = key, at = sched.now })
			if store.latency > 0 then
				sched.wait(store.latency)
			end
			if store.failAll or store.failNext > 0 then
				if store.failNext > 0 then
					store.failNext -= 1
				end
				error("simulated DataStore outage", 0)
			end
		end
		function store.UpdateAsync(_, key, fn)
			begin("UpdateAsync", key)
			local new = fn(deepCopy(store.data[key]))
			if new == nil then
				return nil
			end
			store.data[key] = deepCopy(new)
			store.commits += 1
			return deepCopy(new)
		end
		function store.GetAsync(_, key)
			begin("GetAsync", key)
			return deepCopy(store.data[key])
		end
		return store
	end
	local DataStoreService = make("Folder", { Name = "DataStoreService" })
	state[DataStoreService].props.GetDataStore = function(_, name, scope)
		local key = `{name}/{scope}`
		local pool = world.sharedStores or world.stores
		if not pool[key] then
			pool[key] = newStore(key)
		end
		world.stores[key] = pool[key]
		return pool[key]
	end

	local servicesByName = {
		Players = Players,
		CollectionService = CollectionService,
		ReplicatedStorage = ReplicatedStorage,
		RunService = RunService,
		DataStoreService = DataStoreService,
		Workspace = workspaceNode,
	}
	local game = {
		JobId = world.jobId,
		PlaceId = 0,
		GetService = function(_, name)
			return servicesByName[name] or make("Folder", { Name = name })
		end,
		BindToClose = function(_, fn)
			table.insert(world.closeCallbacks, fn)
		end,
	}

	-- Players ------------------------------------------------------------------------------------------------
	local CHARACTER_PARTS = { "UpperTorso", "LowerTorso", "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand" }

	classInit.Player = function(node, props)
		props.CharacterAdded = newSignal(world)
		props.HasAppearanceLoaded = function()
			return true
		end
		props.Kick = function(self, message)
			world.kicked[self.UserId] = message or ""
			world:leave(self)
		end
		props.LoadCharacterAsync = function(self)
			if self.Character then
				methods.Destroy(self.Character)
			end
			local character = make("Model", { Name = self.Name })
			local humanoid = make("Humanoid", {})
			humanoid.Parent = character
			local hrp = make("Part", { Name = "HumanoidRootPart" })
			hrp.Position = self.spawnAt or roblox.Vector3.new(0, 5, 0)
			hrp.Parent = character
			for _, limb in CHARACTER_PARTS do
				make("Part", { Name = limb }).Parent = character
			end
			character.Parent = workspaceNode
			self.Character = character
			self.CharacterAdded:Fire(character)
			return character
		end
	end

	-- Fake player joins; the real services react through PlayerAdded.
	function world:join(userId, name)
		local player = make("Player", { Name = name or `Player{userId}`, UserId = userId })
		player.Parent = Players
		table.insert(playerList, player)
		playersState.PlayerAdded:Fire(player)
		return player
	end

	-- A leave is two engine steps: PlayerRemoving fires while the player is still parented, then the player detaches.
	-- Tests can pause between them (beginLeave / finishLeave) to hit the narrow windows real servers produce.
	function world:beginLeave(player)
		if table.find(playerList, player) then
			playersState.PlayerRemoving:Fire(player)
		end
	end

	function world:finishLeave(player)
		local i = table.find(playerList, player)
		if i then
			table.remove(playerList, i)
			player.Parent = nil
		end
	end

	function world:leave(player)
		self:beginLeave(player)
		self:finishLeave(player)
	end

	function world:placeCharacter(player, position)
		player.Character.HumanoidRootPart.Position = position
	end

	-- workspace:GetServerTimeNow() as the server reports it
	function world:serverNow()
		return EPOCH + sched.now
	end

	-- A tagged part in the world (Skyport terminal, training station...).
	function world:addTagged(tag, position, attributes)
		local part = make("Part", { Name = tag })
		part.Position = position
		for k, v in attributes or {} do
			part:SetAttribute(k, v)
		end
		part.Parent = workspaceNode
		state[CollectionService].props.AddTag(CollectionService, part, tag)
		return part
	end

	-- Unix time as the server sees it (os.time()).
	function world:time()
		return EPOCH + math.floor(sched.now)
	end

	-- Runs `fn` as a scheduler thread and returns a handle: { done, results }.
	function world:run(fn, ...)
		local handle = { done = false, results = nil }
		sched.spawn(function(...)
			handle.results = table.pack(fn(...))
			handle.done = true
		end, ...)
		return handle
	end

	function world:advance(seconds)
		sched.advance(seconds)
	end

	function world:fireHeartbeat()
		state[RunService].props.Heartbeat:Fire(1 / 60)
	end

	-- Everything sent to a client on a remote, in order.
	function world:sent(remote, player)
		local out = {}
		for _, f in self.fired do
			if f.remote == remote and (player == nil or f.player == player) then
				table.insert(out, f.args)
			end
		end
		return out
	end

	function world:clearSent()
		table.clear(self.fired)
	end

	-- Invokes the server's RemoteFunction exactly as a client would.
	function world:invoke(player, action, args)
		local remote = ReplicatedStorage:FindFirstChild("ArmforgeRemotes"):FindFirstChild("Request")
		return remote.OnServerInvoke(player, action, args)
	end

	function world:fire(remote, player, ...)
		ReplicatedStorage:FindFirstChild("ArmforgeRemotes"):FindFirstChild(remote).OnServerEvent:Fire(player, ...)
	end

	-- BindToClose as the engine runs it: callbacks execute as threads, the server is allowed `grace` seconds.
	function world:shutdown(grace)
		local pending = 0
		for _, fn in self.closeCallbacks do
			pending += 1
			sched.spawn(function()
				fn()
				pending -= 1
			end)
		end
		local waited = 0
		while pending > 0 and waited < (grace or 30) do
			sched.advance(0.05)
			waited += 0.05
		end
		return pending == 0
	end

	function world:assertNoErrors()
		if #sched.errors > 0 then
			error("scheduler thread errors:\n" .. table.concat(sched.errors, "\n---\n"), 2)
		end
	end

	-- Module universe -----------------------------------------------------------------------------------------
	local fakeOs = setmetatable({
		clock = function()
			return sched.now
		end,
		time = function(t)
			if t ~= nil then
				return os.time(t)
			end
			return EPOCH + math.floor(sched.now)
		end,
	}, { __index = os })

	local rockBuilder = {
		TAG = "ArmRock",
		preload = function() end,
		build = function(_, _, _, id, parent)
			world.rockBuilds[id] = (world.rockBuilds[id] or 0) + 1
			local model = make("Model", { Name = `Rock_{id}` })
			local collider = make("Part", { Name = "Collider" })
			collider.CanCollide = true
			collider.Parent = model
			model.Parent = parent
			return { model = model, chunks = {}, collider = collider }
		end,
		rubble = function(_, _, _, id, parent)
			local model = make("Model", { Name = `Rubble_{id}` })
			model.Parent = parent
			return model
		end,
	}
	local armBuilder = {
		MODEL_NAME = "ArmforgeArms",
		attach = function(character, recipe)
			local old = character:FindFirstChild("ArmforgeArms")
			if old then
				old:Destroy()
			end
			local model = make("Model", { Name = "ArmforgeArms" })
			model:SetAttribute("ArmId", recipe.armId)
			model.Parent = character
			table.insert(world.armAttachments, { character = character, armId = recipe.armId, recipe = recipe })
			return model
		end,
	}

	world.universe = Loader.new({
		server = true,
		env = function(root)
			Shared = root
			return {
				game = game,
				workspace = workspaceNode,
				task = {
					spawn = sched.spawn,
					defer = sched.defer,
					delay = sched.delay,
					wait = sched.wait,
				},
				os = fakeOs,
				warn = function(...)
					local parts = {}
					for _, v in { ... } do
						table.insert(parts, tostring(v))
					end
					table.insert(world.warnings, table.concat(parts, " "))
				end,
				print = function() end,
				Instance = {
					new = function(class)
						return make(class)
					end,
				},
				RaycastParams = { new = function() return {} end },
			}
		end,
		replace = {
			["Runtime/ArmBuilder"] = armBuilder,
			["server:World/RockBuilder"] = rockBuilder,
		},
	})

	world.Players = Players
	world.playerList = playerList
	function world:load(path)
		return self.universe:loadServer(path)
	end
	function world:shared(path)
		return self.universe:load(path)
	end

	-- Mirrors Main.server.luau for the services under test (no terrain / WorldBuilder).
	function world:boot()
		local Net = self:shared("Net")
		Net.server()
		local DataService = self:load("Services/DataService")
		DataService.init()
		local RockService = self:load("Services/RockService")
		RockService.init(make("Folder", { Name = "ArmforgeWorld" }))
		RockService.populate() -- no terrain in the fake world, so it places nothing; it does start the burn loop
		local ProgressService = self:load("Services/ProgressService")
		ProgressService.init()
		RockService.setRewardHandler(ProgressService.rockReward)
		self:load("Services/Sync").start()
		self:load("Services/CombatService").start()
		self:load("Services/TrainingService").start()
		self:load("Services/ProgressionServices").start()
		self:load("Services/Requests").start()
		DataService.start()
		self:load("Services/PlayerService").start()
		return {
			DataService = DataService,
			RockService = RockService,
			Sessions = self:load("Services/Sessions"),
			ProgressService = ProgressService,
			Sync = self:load("Services/Sync"),
		}
	end

	return world
end

return ServerWorld
