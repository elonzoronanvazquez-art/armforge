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
local ZoneConfig = require(Shared.Config.Zones)
local Geometry = require(Shared.Logic.RockGeometry)
local RockSim = require(Shared.Logic.RockSim)
local RespawnGuard = require(Shared.Logic.RespawnGuard)
local SpatialGrid = require(Shared.Logic.SpatialGrid)
local CreatureConfig = require(Shared.Config.Creatures)
local EncounterInfo = require(Shared.Logic.EncounterInfo)
local Rng = require(Shared.Util.Rng)
local RockBuilder = require(script.Parent.Parent.World.RockBuilder)
local Sessions = require(script.Parent.Sessions)

local RockService = {}

export type Entry = {
	id: number,
	state: RockSim.State,
	def: RockConfig.RockDef,
	island: string,
	base: CFrame,
	seed: number,
	model: Model?,
	collider: BasePart?, -- the solid hitbox of the current model (nil while destroyed)
	chunks: { [number]: BasePart },
	rubble: Model?,
	burn: { userId: number, dps: number, untilT: number, nextTick: number }?,
	center: Vector3,
}

local rocks: { [number]: Entry } = {}
-- Rocks never move horizontally, so a grid over their base positions answers "what is near this point" without
-- scanning every rock. maxExtent is the largest rock radius, the margin a query needs on top of its own radius.
local grid = SpatialGrid.new(32)
local maxExtent = 0
-- rocks that are currently burning: the burn loop only visits these instead of every rock
local burning: { [number]: Entry } = {}
local container: Folder
local remotes: Net.Remotes
local rewardHandler: ((Player, RockSim.Reward, Entry) -> ())? = nil

-- EncounterService registers itself here (like the reward handler, to avoid a circular require). The rock hands over at its
-- final hit; the encounter later asks for the respawn once the creature is gone.
export type EncounterHandler = {
	begin: (Entry, Player?) -> boolean, -- a creature was released: the rock must NOT respawn by itself
	canDamage: (Entry, number) -> boolean, -- guardian seals only open for eligible players
	onRespawn: (Entry) -> (),
}
local encounterHandler: EncounterHandler? = nil
local rng = Rng.new(os.time())

-- Public hooks -------------------------------------------------------------------------------------------------

-- ProgressService registers itself here to avoid a circular require.
function RockService.setRewardHandler(fn: (Player, RockSim.Reward, Entry) -> ())
	rewardHandler = fn
end

function RockService.setEncounterHandler(handler: EncounterHandler)
	encounterHandler = handler
end

function RockService.get(id: number): Entry?
	return rocks[id]
end

function RockService.all(): { [number]: Entry }
	return rocks
end

-- Alive rocks within `radius` of `pos` (measured to the rock's centre, plus the rock's own radius), nearest first.
function RockService.near(pos: Vector3, radius: number, exclude: number?): { Entry }
	local out: { { e: Entry, d: number } } = {}
	for _, id in grid:query(pos.X, pos.Z, radius + maxExtent) do
		local e = rocks[id]
		if e and id ~= exclude and e.state.alive then
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

-- Sends an effect to every player whose character is within `radius` of `pos`. One pass over the players with no
-- allocation: it is called for every strike, hit and break.
function RockService.fxNear(pos: Vector3, kind: string, payload: any, radius: number?)
	local r = radius or Game.Combat.fxRadius
	local r2 = r * r
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			local d = hrp.Position - pos
			if d:Dot(d) <= r2 then
				remotes.Fx:FireClient(player, kind, payload)
			end
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
	entry.collider = built.collider
	entry.chunks = built.chunks
	built.model:SetAttribute("Hp", entry.state.hp)
	built.model:SetAttribute("Stage", entry.state.stage)
	built.model:SetAttribute("Generation", entry.state.generation)
	built.model:SetAttribute("Island", entry.island)
	-- what is inside, for the client to show on the targeted rock
	local creature = CreatureConfig.Defs[entry.def.encounter]
	if creature then
		built.model:SetAttribute("Size", entry.def.size)
		for k, v in EncounterInfo.forCreature(creature, entry.def.size, entry.island) :: any do
			built.model:SetAttribute(k, v)
		end
	end
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
		collider = nil,
		chunks = {},
		rubble = nil,
		burn = nil,
		center = base * layout.center,
	}
	rocks[id] = entry
	grid:insert(id, base.Position.X, base.Position.Z)
	maxExtent = math.max(maxExtent, layout.radius)
	buildModel(entry)
	return entry
end

-- Root-part positions of every character currently in the server (the only thing a respawn has to keep clear).
local function playerPositions(): { Vector3 }
	local out: { Vector3 } = {}
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			table.insert(out, hrp.Position)
		end
	end
	return out
end

local function footprintBlocked(entry: Entry, layout: Geometry.Layout): boolean
	return RespawnGuard.blocked(entry.base.Position, layout.radius, layout.height, playerPositions(), Game.Rocks.respawnClearance)
end

-- A rock that had to come back while someone still stands in it is non-solid ("ghost") until they move away, so
-- it can neither shove nor trap them. One watcher per model; it retires itself if the rock dies or is rebuilt.
local function watchGhost(entry: Entry)
	local collider, model = entry.collider, entry.model
	if not (collider and model) then
		return
	end
	collider.CanCollide = false
	model:SetAttribute("Ghost", true)
	local token = entry.state.generation
	local function watch()
		if rocks[entry.id] ~= entry or entry.state.generation ~= token or entry.collider ~= collider or not entry.state.alive then
			return
		end
		if footprintBlocked(entry, entry.state.layout) then
			task.delay(Game.Rocks.respawnRetry, watch)
			return
		end
		collider.CanCollide = true
		model:SetAttribute("Ghost", nil)
	end
	task.delay(Game.Rocks.respawnRetry, watch)
end

local function respawn(entry: Entry, seed: number, layout: Geometry.Layout, solid: boolean)
	if entry.rubble then
		entry.rubble:Destroy()
		entry.rubble = nil
	end
	RockSim.respawn(entry.state)
	entry.burn = nil
	-- a fresh layout each life so rocks do not look identical every time
	entry.seed = seed
	entry.state.layout = layout
	entry.center = entry.base * layout.center
	buildModel(entry)
	if not solid then
		watchGhost(entry)
	end
	if encounterHandler then
		encounterHandler.onRespawn(entry)
	end
	RockService.fxNear(entry.center, "Spawn", { id = entry.id, pos = entry.center, def = entry.def.id, radius = entry.state.layout.radius })
end

-- Brings a destroyed rock back, but never on top of a player: while anyone stands in (or right beside) the new
-- footprint the respawn is held back and re-checked every respawnRetry seconds, without moving or touching them.
-- After respawnMaxDefer it returns as a non-solid ghost instead, so an idle player cannot stall a rock forever.
local function attemptRespawn(entry: Entry, token: number, seed: number, layout: Geometry.Layout, heldSince: number?)
	if rocks[entry.id] ~= entry or entry.state.generation ~= token or entry.state.alive then
		return
	end
	if not footprintBlocked(entry, layout) then
		respawn(entry, seed, layout, true)
		return
	end
	local since = heldSince or os.clock()
	if os.clock() - since >= Game.Rocks.respawnMaxDefer then
		respawn(entry, seed, layout, false)
		return
	end
	task.delay(Game.Rocks.respawnRetry, attemptRespawn, entry, token, seed, layout, since)
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
	entry.collider = nil
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

	-- one-time MINING payout. A rock that holds a creature pays only its mining share here; the creature pays the rest through
	-- the encounter's own single reward path, so nothing is paid twice.
	local holdsCreature = encounterHandler ~= nil and CreatureConfig.Defs[entry.def.encounter] ~= nil
	local share = if holdsCreature then entry.def.miningShare else 1
	local rewards = RockSim.payout(state, rng)
	if rewards and rewardHandler then
		for userId, reward in rewards do
			local player = Players:GetPlayerByUserId(userId)
			if player then
				if share < 1 then
					reward = {
						coins = math.floor(reward.coins * share),
						xp = math.floor(reward.xp * share),
						shards = reward.shards,
						fraction = reward.fraction,
						killer = reward.killer,
					}
				end
				rewardHandler(player, reward, entry)
			end
		end
	end

	-- the creature inside (if any) is released only now, after the authoritative final hit; it then owns the respawn
	if holdsCreature and encounterHandler and encounterHandler.begin(entry, killer) then
		return
	end
	RockService.requestRespawn(entry, Game.Rocks.aftermath + entry.def.respawn)
end

-- Rebuilds a destroyed rock after `delay` seconds (held back while a player stands in its footprint). Safe to call more than
-- once: only the first request for the current death does anything.
function RockService.requestRespawn(entry: Entry, delay: number)
	local token = entry.state.generation
	task.delay(delay, function()
		if rocks[entry.id] == entry and entry.state.generation == token and not entry.state.alive then
			local seed = entry.seed + 17
			attemptRespawn(entry, token, seed, Geometry.generate(entry.def, seed), nil)
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
	if encounterHandler and not encounterHandler.canDamage(entry, userId) then
		return nil
	end
	amount *= Sessions.devPower(player) -- developer mode only; 1 for everyone else
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
	burning[entry.id] = entry
	if entry.model then
		entry.model:SetAttribute("Burning", true)
	end
end

local function burnLoop()
	while true do
		task.wait(0.5)
		local now = os.clock()
		for id, entry in burning do
			local burn = entry.burn
			if burn and entry.state.alive then
				if now >= burn.nextTick then
					burn.nextTick += 1
					local player = Players:GetPlayerByUserId(burn.userId)
					RockService.damage(entry, player, burn.userId, burn.dps, { silent = true, power = 0.3 })
				end
				if burn.untilT <= now then
					entry.burn = nil
					burning[id] = nil
					if entry.model then
						entry.model:SetAttribute("Burning", nil)
					end
				end
			else
				entry.burn = nil
				burning[id] = nil
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

-- The nearest sensible ground to a guardian's configured seal position (flat terrain, not water), searched outward in rings.
local function sealSpot(want: Vector3): Vector3?
	for ringRadius = 0, 48, 8 do
		local steps = if ringRadius == 0 then 1 else 10
		for i = 0, steps - 1 do
			local angle = (i / steps) * math.pi * 2
			local pos, normal = groundAt(want.X + math.cos(angle) * ringRadius, want.Z + math.sin(angle) * ringRadius)
			if pos and normal and normal.Y > 0.93 then
				return pos
			end
		end
	end
	return nil
end

-- Places every configured rock of a list of fields; returns the new running total (stops at the global cap).
local function populateFields(islandId: string, fields: { IslandConfig.Field }, taken: { Vector3 }, total: number): number
	for fi, field in fields do
		for ri, entry in field.rocks do
			local def = RockConfig.Defs[entry.rock]
			local seed = (fi * 1000 + ri * 100) + #islandId * 7
			local points = spawnPoints(islandId, field, entry.count, taken, seed)
			for i, pos in points do
				if total >= Game.Rocks.maxActive then
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
	return total
end

-- Spawns every configured rock and each island's guardian seal. Call after the island ground exists.
function RockService.populate(): number
	local total = 0
	for _, islandId in IslandConfig.Order do
		local island = IslandConfig.Defs[islandId]
		local taken: { Vector3 } = {}
		local guardian = island.guardian
		if guardian then
			local spot = sealSpot(guardian.position)
			if spot then
				spawnRock(RockConfig.Defs[guardian.seal], islandId, spot, 7000 + #islandId * 13)
				table.insert(taken, spot)
				total += 1
			else
				warn(`[ARMFORGE] could not place the {islandId} guardian seal near {guardian.position}`)
			end
		end
		local minis: { IslandConfig.MiniBossDef } = island.miniBosses or {}
		for mi, mini in minis do
			local spot = sealSpot(mini.position)
			if spot then
				spawnRock(RockConfig.Defs[mini.seal], islandId, spot, 8000 + mi * 31 + #islandId * 13)
				table.insert(taken, spot)
				total += 1
			else
				warn(`[ARMFORGE] could not place the {islandId} mini boss seal {mini.seal} near {mini.position}`)
			end
		end
		total = populateFields(islandId, island.fields, taken, total)
		if total >= Game.Rocks.maxActive then
			warn("[ARMFORGE] rock cap reached")
			return total
		end
	end
	-- zones (The Atlantic Sea): rocks only, no seals
	for _, zoneId in ZoneConfig.Order do
		local zone = ZoneConfig.Defs[zoneId]
		total = populateFields(zoneId, zone.fields, {}, total)
	end
	task.spawn(burnLoop)
	return total
end

-- Test / dev helper: spawns one rock at a position.
function RockService.spawnAt(defId: string, pos: Vector3, island: string?): Entry
	return spawnRock(RockConfig.Defs[defId], island or "Forgeheart", pos, os.time() % 10000)
end

return RockService
