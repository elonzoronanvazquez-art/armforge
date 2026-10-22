--!strict
-- Owns every live rock: placement, authoritative state (shared/Logic/RockSim), chunk stripping, collapse, payouts,
-- burning, respawn. Combat calls damage(); nothing else mutates a rock. Effects are NOT simulated here: the server
-- only tells nearby clients what broke (Fx remote) and they render sparks/debris themselves.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local Net = require(Shared.Net)
local Game = require(Shared.Config.Game)
local RockConfig = require(Shared.Config.Rocks)
local IslandConfig = require(Shared.Config.Islands)
local Geometry = require(Shared.Logic.RockGeometry)
local RockSim = require(Shared.Logic.RockSim)
local Rng = require(Shared.Util.Rng)
local RockBuilder = require(script.Parent.Parent.World.RockBuilder)

local RockService = {}

export type Entry = {
	id: number,
	state: RockSim.State,
	def: RockConfig.RockDef,
	island: string,
	base: CFrame,
	seed: number,
	model: Model?,
	chunks: { [number]: BasePart },
	rubble: Model?,
	burn: { userId: number, dps: number, untilT: number, nextTick: number }?,
	center: Vector3,
}

local rocks: { [number]: Entry } = {}
local container: Folder
local remotes: Net.Remotes
local rewardHandler: ((Player, RockSim.Reward, Entry) -> ())? = nil
local rng = Rng.new(os.time())

-- Public hooks -------------------------------------------------------------------------------------------------

-- ProgressService registers itself here to avoid a circular require.
function RockService.setRewardHandler(fn: (Player, RockSim.Reward, Entry) -> ())
	rewardHandler = fn
end

function RockService.get(id: number): Entry?
	return rocks[id]
end

function RockService.all(): { [number]: Entry }
	return rocks
end

-- Alive rocks within `radius` of `pos`, nearest first.
function RockService.near(pos: Vector3, radius: number, exclude: number?): { Entry }
	local out: { { e: Entry, d: number } } = {}
	for id, e in rocks do
		if id ~= exclude and e.state.alive then
			local d = (e.center - pos).Magnitude
			if d <= radius + e.state.layout.radius then
				table.insert(out, { e = e, d = d })
			end
		end
	end
	table.sort(out, function(a: { e: Entry, d: number }, b: { e: Entry, d: number })
		return a.d < b.d
	end)
	local list = {}
	for _, o in out do
		table.insert(list, o.e)
	end
	return list
end

-- Distance check used by combat: the strike must come from within reach of the rock's surface (+ latency slack).
function RockService.inReach(entry: Entry, pos: Vector3, reach: number, extra: number): boolean
	if not entry.state.alive then
		return false
	end
	local d = (entry.center - pos).Magnitude
	return d <= reach + entry.state.layout.radius + extra
end

-- FX broadcast ------------------------------------------------------------------------------------------------

function RockService.fxNear(pos: Vector3, kind: string, payload: any, radius: number?)
	local r2 = (radius or Game.Combat.fxRadius) ^ 2
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp and (hrp.Position - pos).Magnitude ^ 2 <= r2 then
			remotes.Fx:FireClient(player, kind, payload)
		end
	end
end

local function chunkInfo(entry: Entry, index: number): any
	local chunk = entry.state.layout.chunks[index]
	local part = entry.chunks[index]
	local cf = if part then part.CFrame else entry.base * CFrame.new(chunk.pos)
	return { p = cf.Position, s = chunk.size, c = if part then part.Color else entry.def.colors.shell, m = if part then part.Material.Value else 0, l = chunk.layer }
end

-- Placement ----------------------------------------------------------------------------------------------------

local function groundAt(x: number, z: number): (Vector3?, Vector3?)
	-- terrain only, so rocks never land on props or other rocks
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -800, 0), params)
	if hit and hit.Material ~= Enum.Material.Water then
		return hit.Position, hit.Normal
	end
	return nil, nil
end

local function spawnPoints(islandId: string, field: IslandConfig.Field, count: number, taken: { Vector3 }, seed: number): { Vector3 }
	local r = Rng.new(seed)
	local points: { Vector3 } = {}
	local attempts = 0
	while #points < count and attempts < count * 60 do
		attempts += 1
		local angle = r:range(0, math.pi * 2)
		local dist = math.sqrt(r:next()) * field.radius
		local x, z = field.center.X + math.cos(angle) * dist, field.center.Z + math.sin(angle) * dist
		local ok = true
		for _, other in taken do
			if (Vector3.new(x, 0, z) - Vector3.new(other.X, 0, other.Z)).Magnitude < Game.Rocks.minSpacing then
				ok = false
				break
			end
		end
		if ok then
			local pos, normal = groundAt(x, z)
			if pos and normal and normal.Y > 0.86 then
				table.insert(points, pos)
				table.insert(taken, pos)
			end
		end
	end
	return points
end

-- Rock lifecycle -----------------------------------------------------------------------------------------------

local nextId = 1

local function buildModel(entry: Entry)
	local layout = entry.state.layout
	local built = RockBuilder.build(entry.def, layout, entry.base, entry.id, container)
	entry.model = built.model
	entry.chunks = built.chunks
	built.model:SetAttribute("Hp", entry.state.hp)
	built.model:SetAttribute("Stage", entry.state.stage)
	built.model:SetAttribute("Generation", entry.state.generation)
	built.model:SetAttribute("Island", entry.island)
end

local function spawnRock(def: RockConfig.RockDef, island: string, pos: Vector3, seed: number): Entry
	local layout = Geometry.generate(def, seed)
	local id = nextId
	nextId += 1
	local yaw = Rng.new(seed + 11):range(0, math.pi * 2)
	local base = CFrame.new(pos + Vector3.new(0, Game.Rocks.groundOffset, 0)) * CFrame.Angles(0, yaw, 0)
	local entry: Entry = {
		id = id,
		state = RockSim.new(id, def, layout),
		def = def,
		island = island,
		base = base,
		seed = seed,
		model = nil,
		chunks = {},
		rubble = nil,
		burn = nil,
		center = base * layout.center,
	}
	rocks[id] = entry
	buildModel(entry)
	return entry
end

local function respawn(entry: Entry)
	if entry.rubble then
		entry.rubble:Destroy()
		entry.rubble = nil
	end
	RockSim.respawn(entry.state)
	entry.burn = nil
	-- a fresh layout each life so rocks do not look identical every time
	entry.seed += 17
	entry.state.layout = Geometry.generate(entry.def, entry.seed)
	entry.center = entry.base * entry.state.layout.center
	buildModel(entry)
	RockService.fxNear(entry.center, "Spawn", { id = entry.id, pos = entry.center, def = entry.def.id, radius = entry.state.layout.radius })
end

local function collapse(entry: Entry, result: RockSim.ApplyResult, killer: Player?)
	local state = entry.state
	local infos = {}
	-- cap the chunks sent to clients (they cap debris again on their side)
	local list = result.collapse
	for i = 1, math.min(#list, 14) do
		table.insert(infos, chunkInfo(entry, list[i]))
	end
	local model = entry.model
	entry.chunks = {}
	if model then
		model:SetAttribute("Alive", false)
		model:SetAttribute("Hp", 0)
		model:SetAttribute("Stage", "COLLAPSE")
		CollectionService:RemoveTag(model, RockBuilder.TAG)
		task.defer(function()
			model:Destroy()
		end)
	end
	entry.model = nil
	entry.rubble = RockBuilder.rubble(entry.def, state.layout, entry.base, entry.id, container)

	RockService.fxNear(entry.center, "Break", {
		id = entry.id,
		pos = entry.center,
		def = entry.def.id,
		radius = state.layout.radius,
		height = state.layout.height,
		chunks = infos,
		killer = if killer then killer.UserId else 0,
	})

	-- one-time payout
	local rewards = RockSim.payout(state, rng)
	if rewards and rewardHandler then
		for userId, reward in rewards do
			local player = Players:GetPlayerByUserId(userId)
			if player then
				rewardHandler(player, reward, entry)
			end
		end
	end

	local token = state.generation
	task.delay(Game.Rocks.aftermath + entry.def.respawn, function()
		if rocks[entry.id] == entry and entry.state.generation == token and not entry.state.alive then
			respawn(entry)
		end
	end)
end

export type DamageOpts = {
	hitDir: Vector3?, -- world-space unit vector from the rock toward the attacker
	hitPos: Vector3?,
	minChunks: number?,
	crit: boolean?,
	rend: boolean?,
	finisher: boolean?,
	skill: string?,
	power: number?, -- visual weight 0..2
	armId: string?,
	extraChunks: number?,
	silent: boolean?, -- splash / burn: reduced effects
	trailColor: Color3?,
}

-- Applies authoritative damage. Returns the sim result (nil if the rock is dead or the damage was invalid).
function RockService.damage(entry: Entry, player: Player?, userId: number, amount: number, opts: DamageOpts): RockSim.ApplyResult?
	local state = entry.state
	if not state.alive then
		return nil
	end
	local hitDirWorld = opts.hitDir
	local dirLocal: Vector3? = nil
	if hitDirWorld then
		local localDir = entry.base:VectorToObjectSpace(hitDirWorld)
		if localDir.Magnitude > 1e-3 then
			dirLocal = localDir.Unit
		end
	end
	local minChunks = opts.minChunks or 0
	if opts.extraChunks and opts.extraChunks > 0 then
		minChunks = math.max(minChunks, opts.extraChunks)
	end
	local result = RockSim.apply(state, userId, amount, dirLocal, if minChunks > 0 then minChunks else nil)
	if result.ignored then
		return nil
	end

	local model = entry.model
	if model and not result.killed then
		model:SetAttribute("Hp", state.hp)
		if result.stageChanged then
			model:SetAttribute("Stage", state.stage)
		end
	end

	-- chunk removal (collected for the effect payload BEFORE destroying the parts)
	local infos = {}
	for _, idx in result.removed do
		table.insert(infos, chunkInfo(entry, idx))
		local part = entry.chunks[idx]
		if part then
			part:Destroy()
			entry.chunks[idx] = nil
		end
	end

	local center = entry.center
	local hitPos = opts.hitPos or (center + (hitDirWorld or Vector3.yAxis) * (entry.state.layout.radius * 0.8))
	if not opts.silent then
		RockService.fxNear(center, "Hit", {
			id = entry.id,
			pos = hitPos,
			dir = hitDirWorld or Vector3.yAxis,
			dmg = result.applied,
			crit = opts.crit == true,
			rend = opts.rend == true,
			finisher = opts.finisher == true,
			skill = opts.skill,
			power = opts.power or 1,
			stage = if result.killed then "COLLAPSE" else state.stage,
			stageChanged = result.stageChanged,
			frac = result.hpFrac,
			def = entry.def.id,
			armId = opts.armId,
			chunks = infos,
			attacker = userId,
			trail = opts.trailColor,
			seed = rng:int(1, 9999),
		})
	elseif #infos > 0 then
		RockService.fxNear(center, "Hit", {
			id = entry.id,
			pos = hitPos,
			dir = hitDirWorld or Vector3.yAxis,
			dmg = result.applied,
			crit = false,
			power = 0.4,
			stage = state.stage,
			frac = result.hpFrac,
			def = entry.def.id,
			chunks = infos,
			attacker = userId,
			quiet = true,
			seed = rng:int(1, 9999),
		})
	end

	if result.killed then
		collapse(entry, result, player)
	end
	return result
end

-- Burning (Magma Arms) -------------------------------------------------------------------------------------

function RockService.ignite(entry: Entry, userId: number, dps: number, duration: number)
	if not entry.state.alive then
		return
	end
	local now = os.clock()
	entry.burn = { userId = userId, dps = dps, untilT = now + duration, nextTick = now + 1 }
	if entry.model then
		entry.model:SetAttribute("Burning", true)
	end
end

local function burnLoop()
	while true do
		task.wait(0.5)
		local now = os.clock()
		for _, entry in rocks do
			local burn = entry.burn
			if burn and entry.state.alive then
				if now >= burn.nextTick then
					burn.nextTick += 1
					local player = Players:GetPlayerByUserId(burn.userId)
					RockService.damage(entry, player, burn.userId, burn.dps, { silent = true, power = 0.3 })
				end
				if now >= burn.untilT then
					entry.burn = nil
					if entry.model then
						entry.model:SetAttribute("Burning", nil)
					end
				end
			elseif burn then
				entry.burn = nil
			end
		end
	end
end

-- Setup --------------------------------------------------------------------------------------------------------

function RockService.init(worldFolder: Folder)
	remotes = Net.server()
	container = Instance.new("Folder")
	container.Name = "Rocks"
	container.Parent = worldFolder
end

-- Spawns every configured rock. Call after the island ground exists.
function RockService.populate(): number
	local total = 0
	for _, islandId in IslandConfig.Order do
		local island = IslandConfig.Defs[islandId]
		local taken: { Vector3 } = {}
		for fi, field in island.fields do
			for ri, entry in field.rocks do
				local def = RockConfig.Defs[entry.rock]
				local seed = (fi * 1000 + ri * 100) + #islandId * 7
				local points = spawnPoints(islandId, field, entry.count, taken, seed)
				for i, pos in points do
					if total >= Game.Rocks.maxActive then
						warn("[ARMFORGE] rock cap reached")
						return total
					end
					spawnRock(def, islandId, pos, seed + i * 13)
					total += 1
				end
				if #points < entry.count then
					warn(`[ARMFORGE] only placed {#points}/{entry.count} {entry.rock} in {field.name}`)
				end
			end
		end
	end
	task.spawn(burnLoop)
	return total
end

-- Test / dev helper: spawns one rock at a position.
function RockService.spawnAt(defId: string, pos: Vector3, island: string?): Entry
	return spawnRock(RockConfig.Defs[defId], island or "Forgeheart", pos, os.time() % 10000)
end

return RockService
