--!strict
-- Rock encounters: the creature imprisoned in a rock and the lifecycle around it.
--
--   rock destroyed (RockService.collapse) --begin--> REVEAL (creature emerges, invulnerable) --> COMBAT (Logic/CreatureSim)
--       --> DEFEATED (single reward path) --> RECOVERY (corpse removed) --> RESPAWNING (rock rebuilt) --> SEALED
--   an abandoned creature (nobody around for a long time) retreats: COMBAT/REVEAL --> RECOVERY with no reward.
--
-- Every transition goes through Logic/EncounterSM, so a duplicate final hit, a late timer from a previous life or a second
-- reward attempt is refused instead of spawning, paying or reviving anything twice. The server owns all creature state; clients
-- only render it (model attributes + the Fx remote). Encounters are SHARED: any eligible player in reach can hurt the creature,
-- rewards are split by contribution (CreatureSim.payout), and guardian completion is granted per eligible contributor.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local Net = require(Shared.Net)
local CreatureConfig = require(Shared.Config.Creatures)
local RockConfig = require(Shared.Config.Rocks)
local CreatureSim = require(Shared.Logic.CreatureSim)
local EncounterSM = require(Shared.Logic.EncounterSM)
local Guardians = require(Shared.Logic.Guardians)
local Rng = require(Shared.Util.Rng)
local Sessions = require(script.Parent.Sessions)
local RockService = require(script.Parent.RockService)
local ProgressService = require(script.Parent.ProgressService)
local CreatureBuilder = require(script.Parent.Parent.World.CreatureBuilder)

local EncounterService = {}

export type Enc = {
	id: number,
	entry: RockService.Entry,
	def: CreatureConfig.CreatureDef,
	sm: EncounterSM.Encounter,
	sim: CreatureSim.Sim?,
	model: Model?,
	lastStep: number,
	published: { [string]: any },
}

local encounters: { [number]: Enc } = {}
local active: { [number]: Enc } = {} -- encounters with a live creature that needs stepping
local container: Folder
local remotes: Net.Remotes
local rng = Rng.new(os.time() + 99)
local lastWarn: { [number]: number } = {}

-- Helpers ------------------------------------------------------------------------------------------------------------------

local function now(): number
	return os.clock()
end

-- os.clock time -> workspace server time (what clients animate against)
local function serverTime(t: number): number
	return workspace:GetServerTimeNow() + (t - os.clock())
end

local function flatDist(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function referenceRock(enc: Enc): RockConfig.RockDef
	return RockConfig.Defs[enc.def.refRock or enc.entry.def.id]
end

local function rewardBase(enc: Enc): { coins: number, xp: number, shards: number }
	local ref = referenceRock(enc)
	return {
		coins = math.floor(ref.coins * enc.def.reward.coinsMult),
		xp = math.floor(ref.xp * enc.def.reward.xpMult),
		shards = enc.def.reward.shards,
	}
end

local function warnPlayer(player: Player, text: string)
	local t = now()
	if t - (lastWarn[player.UserId] or -1e9) < 4 then
		return
	end
	lastWarn[player.UserId] = t
	ProgressService.notify(player, "Toast", { text = text, kind = "warn" })
end

-- May this session fight this creature? (guardians need the rebirths; the island must be unlocked)
local function eligible(session: Sessions.Session, island: string, tier: string): (boolean, string?)
	local data = session.data
	if not data.islands.unlocked[island] then
		return false, "This island is still locked."
	end
	if tier == "boss" then
		local check = Guardians.canChallenge(data, island)
		if not check.ok then
			return false, `The guardian is sealed. Requires: {table.concat(check.missing, ", ")}.`
		end
	end
	return true, nil
end

-- Publishes the creature's state as model attributes (cheap: SetAttribute replicates only on change). Clients animate from these.
local function publish(enc: Enc)
	local model, sim = enc.model, enc.sim
	if not (model and sim) then
		return
	end
	local status = CreatureSim.status(sim, now())
	local attrs: { [string]: any } = {
		State = sim.state,
		StateStart = serverTime(sim.enteredAt),
		StateEnd = serverTime(sim.endsAt),
		Attack = if sim.attack then sim.attack.id else "",
		AttackKind = if sim.attack then sim.attack.kind else "",
		Hp = math.floor(sim.hp),
		MaxHp = sim.maxHp,
		Phase = sim.phase,
		Alive = sim.alive and sim.state ~= "EMERGING",
		Armored = status.armored,
		CoreUntil = if status.coreOpen then serverTime(sim.coreOpenUntil) else 0,
		ArmorUntil = if status.armorOpen then serverTime(sim.armorOpenUntil) else 0,
		Target = sim.target or 0,
	}
	for k, v in attrs do
		if enc.published[k] ~= v then
			enc.published[k] = v
			model:SetAttribute(k, v)
		end
	end
end

local function playersFor(enc: Enc): { CreatureSim.Player }
	local sim = enc.sim :: CreatureSim.Sim
	local list: { CreatureSim.Player } = {}
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp and flatDist(hrp.Position, sim.home) <= sim.def.leash + 25 then
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local session = Sessions.ready(player)
			table.insert(list, {
				userId = player.UserId,
				pos = hrp.Position,
				alive = hum ~= nil and hum.Health > 0,
				canFight = session ~= nil and (eligible(session, enc.entry.island, enc.def.tier)),
			})
		end
	end
	return list
end

-- Lifecycle ----------------------------------------------------------------------------------------------------------------

local function removeModel(enc: Enc)
	if enc.model then
		enc.model:Destroy()
		enc.model = nil
	end
	enc.published = {}
end

-- Ends the encounter without a victory (nobody left to fight it): the creature retreats and the rock re-seals.
local function retire(enc: Enc, delay: number)
	if not EncounterSM.to(enc.sm, "RECOVERY") then
		return
	end
	active[enc.id] = nil
	if enc.sim then
		RockService.fxNear(enc.sim.pos, "Retreat", { id = enc.id, pos = enc.sim.pos, color = enc.def.visual.glow, radius = enc.def.radius }, 120)
	end
	removeModel(enc)
	enc.sim = nil
	EncounterSM.to(enc.sm, "RESPAWNING")
	RockService.requestRespawn(enc.entry, delay)
end

local function onKilled(enc: Enc, killer: Player?)
	local sim = enc.sim
	if not sim or not EncounterSM.to(enc.sm, "DEFEATED") then
		return -- a second final hit: the first one already ended the fight
	end
	active[enc.id] = nil
	publish(enc)
	local def = enc.def
	local boss = def.tier == "boss"
	local rewards = CreatureSim.payout(sim, rewardBase(enc))
	enc.sm.rewards += 1
	local island = enc.entry.island
	if rewards then
		for userId, reward in rewards do
			local player = Players:GetPlayerByUserId(userId)
			local session = player and Sessions.ready(player)
			if player and session then
				local data = session.data
				data.stats.creaturesDefeated += 1
				local mult = 1
				local first = false
				if boss then
					-- the completion is re-validated by Guardians.recordDefeat itself (rebirths + island access)
					local rec = Guardians.recordDefeat(data, island)
					if rec.ok then
						first = rec.first
						if not first then
							mult = def.repeatMult or 0.15
						end
					else
						mult = 0
					end
				end
				ProgressService.creatureReward(player, {
					coins = math.floor(reward.coins * mult),
					xp = math.floor(reward.xp * mult),
					shards = math.floor(reward.shards * mult),
				}, enc.def, enc.entry, { killer = reward.killer, first = first, boss = boss, victory = boss and mult > 0 })
				if boss and first then
					ProgressService.guardianVictory(player, island)
				end
			end
		end
	end
	RockService.fxNear(sim.pos, "CreatureDefeat", {
		id = enc.id,
		pos = sim.pos,
		name = def.name,
		boss = boss,
		color = def.visual.glow,
		radius = def.radius,
		height = def.height * def.scale * 0.4,
		killer = if killer then killer.UserId else 0,
	}, 140)
	local token = enc.sm.token
	task.delay(CreatureConfig.Config.recovery + (if boss then 3 else 0), function()
		if enc.sm.token ~= token or enc.sm.state ~= "DEFEATED" then
			return
		end
		EncounterSM.to(enc.sm, "RECOVERY")
		removeModel(enc)
		enc.sim = nil
		EncounterSM.to(enc.sm, "RESPAWNING")
		local delay = if boss then CreatureConfig.Config.guardianRespawn else enc.entry.def.respawn
		RockService.requestRespawn(enc.entry, delay)
	end)
end

local function applyEvents(enc: Enc, events: { CreatureSim.Event })
	local sim = enc.sim :: CreatureSim.Sim
	for _, e in events do
		if e.kind == "telegraph" then
			RockService.fxNear(sim.pos, "Telegraph", {
				id = enc.id,
				attack = e.attack,
				shape = e.shape,
				origin = e.origin,
				dir = e.dir,
				radius = e.radius,
				length = e.length,
				width = e.width,
				halfAngle = e.halfAngle,
				dur = e.duration,
				serverT = workspace:GetServerTimeNow(),
				interruptible = e.interruptible,
				text = e.text,
				boss = enc.def.tier == "boss",
			}, 160)
		elseif e.kind == "strike" then
			RockService.fxNear(sim.pos, "CreatureStrike", { id = enc.id, shape = e.shape, origin = e.origin, dir = e.dir, pos = e.pos, color = enc.def.visual.glow, boss = enc.def.tier == "boss" }, 140)
		elseif e.kind == "hit" then
			local player = Players:GetPlayerByUserId(e.userId)
			local char = player and player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if player and hum and hum.Health > 0 then
				hum:TakeDamage(e.damage)
				remotes.Fx:FireClient(player, "Hurt", { dmg = e.damage, id = enc.id, attack = e.attack })
			end
		elseif e.kind == "despawn" then
			retire(enc, 6)
			return
		end
	end
end

local function step(enc: Enc, t: number)
	local sim = enc.sim
	if not sim or not sim.alive then
		return
	end
	local dt = math.min(0.25, t - enc.lastStep)
	enc.lastStep = t
	local events = CreatureSim.step(sim, t, dt, playersFor(enc), rng)
	-- REVEAL ends when the sim leaves EMERGING
	if enc.sm.state == "REVEAL" and sim.state ~= "EMERGING" then
		if EncounterSM.to(enc.sm, "COMBAT") then
			RockService.fxNear(sim.pos, "Engage", { id = enc.id, pos = sim.pos, name = enc.def.name, boss = enc.def.tier == "boss" }, 120)
		end
	end
	if enc.model then
		local pos, facing = sim.pos, sim.facing
		local goal = CFrame.lookAt(pos, pos + Vector3.new(facing.X, 0, facing.Z))
		if enc.model:GetPivot() ~= goal then
			enc.model:PivotTo(goal)
		end
	end
	applyEvents(enc, events)
	if active[enc.id] == enc then
		publish(enc)
	end
end

-- Called by RockService when a rock's final hit lands. Returns true if a creature was released (the rock then waits for us
-- to ask for its respawn); false means "no encounter, respawn the rock normally".
local function begin(entry: RockService.Entry, killer: Player?): boolean
	local def = CreatureConfig.Defs[entry.def.encounter]
	if not def then
		return false
	end
	local enc: Enc
	local existing = encounters[entry.id]
	if existing then
		enc = existing
	else
		local fresh: Enc = { id = entry.id, entry = entry, def = def, sm = EncounterSM.new(), sim = nil, model = nil, lastStep = now(), published = {} }
		encounters[entry.id] = fresh
		enc = fresh
	end
	if not EncounterSM.to(enc.sm, "REVEAL") then
		return false
	end
	enc.entry = entry
	enc.def = def
	local home = Vector3.new(entry.base.Position.X, entry.base.Position.Y, entry.base.Position.Z)
	local maxHp = math.max(1, math.floor(referenceRock(enc).maxHp * def.hpMult))
	enc.sim = CreatureSim.new(entry.id, def, maxHp, home, now())
	enc.lastStep = now()
	local model = CreatureBuilder.build(def, entry.id, home)
	model:SetAttribute("RockId", entry.id)
	model:SetAttribute("CreatureId", def.id)
	model:SetAttribute("DefId", entry.def.id)
	model:SetAttribute("Island", entry.island)
	model:SetAttribute("Radius", def.radius)
	model:SetAttribute("Height", def.height)
	model:SetAttribute("Tier", def.tier)
	model:SetAttribute("Name", def.name)
	model:SetAttribute("Generation", entry.state.generation)
	model:SetAttribute("Alive", false)
	model.Parent = container
	CreatureBuilder.tag(model)
	enc.model = model
	enc.published = {}
	publish(enc)
	active[enc.id] = enc
	RockService.fxNear(home, "Reveal", {
		id = entry.id,
		pos = home,
		def = def.id,
		rock = entry.def.id,
		name = def.name,
		title = def.title,
		tier = def.tier,
		boss = def.tier == "boss",
		radius = def.radius * def.scale,
		height = def.height,
		color = def.visual.glow,
		dur = def.emerge,
		killer = if killer then killer.UserId else 0,
	}, 160)
	return true
end

-- RockService asks permission before it lets a player hurt a rock (guardian seals only open for eligible players).
local function canDamage(entry: RockService.Entry, userId: number): boolean
	if entry.def.size ~= "seal" then
		return true
	end
	local player = Players:GetPlayerByUserId(userId)
	local session = player and Sessions.ready(player)
	if not (player and session) then
		return false
	end
	local ok, reason = eligible(session, entry.island, "boss")
	if not ok and reason then
		warnPlayer(player, reason)
	end
	return ok
end

local function onRockRespawned(entry: RockService.Entry)
	local enc = encounters[entry.id]
	if enc then
		EncounterSM.to(enc.sm, "SEALED")
	end
end

-- Public API ---------------------------------------------------------------------------------------------------------------

function EncounterService.get(id: number): Enc?
	return encounters[id]
end

-- The encounter a strike aimed at `id` should hit: only a creature that is in COMBAT can be hurt.
function EncounterService.targetFor(id: number): Enc?
	local enc = encounters[id]
	if enc and enc.sm.state == "COMBAT" and enc.sim and enc.sim.alive then
		return enc
	end
	return nil
end

-- Fightable creatures whose body is within `radius` of `pos`, nearest first.
function EncounterService.near(pos: Vector3, radius: number): { Enc }
	local out: { { e: Enc, d: number } } = {}
	for _, enc in active do
		local sim = enc.sim
		if sim and sim.alive and enc.sm.state == "COMBAT" then
			local d = flatDist(pos, sim.pos)
			if d <= radius + enc.def.radius then
				table.insert(out, { e = enc, d = d })
			end
		end
	end
	table.sort(out, function(a: { e: Enc, d: number }, b: { e: Enc, d: number })
		return a.d < b.d
	end)
	local list: { Enc } = {}
	for _, o in out do
		table.insert(list, o.e)
	end
	return list
end

function EncounterService.activeCount(): number
	local n = 0
	for _ in active do
		n += 1
	end
	return n
end

-- Reach check for strikes (horizontal distance to the creature's body plus a vertical sanity window).
function EncounterService.inReach(enc: Enc, pos: Vector3, reach: number, extra: number): boolean
	local sim = enc.sim
	if not sim or not sim.alive then
		return false
	end
	local def = enc.def
	return flatDist(pos, sim.pos) <= reach + def.radius + extra and math.abs(pos.Y - sim.pos.Y) <= def.height * def.scale + 8
end

function EncounterService.eligible(session: Sessions.Session, enc: Enc): (boolean, string?)
	return eligible(session, enc.entry.island, enc.def.tier)
end

-- Applies a player's strike to the creature. amount comes from Combat.resolveHit. Returns the sim result (nil if refused).
function EncounterService.hit(enc: Enc, player: Player, amount: number, opts: { skill: string?, crit: boolean?, rend: boolean?, finisher: boolean?, power: number?, armId: string? }): CreatureSim.DamageResult?
	local sim = enc.sim
	local session = Sessions.ready(player)
	if not (sim and session) or enc.sm.state ~= "COMBAT" then
		return nil
	end
	local ok, reason = eligible(session, enc.entry.island, enc.def.tier)
	if not ok then
		if reason then
			warnPlayer(player, reason)
		end
		return nil
	end
	local result = CreatureSim.applyDamage(sim, player.UserId, amount, { skill = opts.skill, crit = opts.crit }, now())
	if result.ignored then
		return nil
	end
	RockService.fxNear(sim.pos, "CreatureHit", {
		id = enc.id,
		pos = sim.pos + Vector3.new(0, enc.def.height * enc.def.scale * 0.35, 0),
		dmg = result.applied,
		crit = opts.crit == true,
		rend = opts.rend == true,
		finisher = opts.finisher == true,
		skill = opts.skill,
		power = opts.power or 1,
		armored = result.armored,
		armorBroken = result.armorBroken,
		coreHit = result.coreHit,
		interrupted = result.interrupted,
		frac = result.hpFrac,
		attacker = player.UserId,
		color = enc.def.visual.glow,
		boss = enc.def.tier == "boss",
	}, 120)
	if result.phaseChanged then
		local phase = if enc.def.phases then enc.def.phases[sim.phase - 1] else nil
		RockService.fxNear(sim.pos, "PhaseChange", {
			id = enc.id,
			pos = sim.pos,
			name = if phase then phase.name else "",
			text = if phase then phase.text else "",
			color = enc.def.visual.glow,
		}, 160)
	end
	publish(enc)
	if result.killed then
		onKilled(enc, player)
	end
	return result
end

function EncounterService.start()
	remotes = Net.server()
	RockService.setEncounterHandler({ begin = begin, canDamage = canDamage, onRespawn = onRockRespawned })
	task.spawn(function()
		while true do
			local any = next(active) ~= nil
			task.wait(if any then CreatureConfig.Config.tickRate else 0.4)
			if any then
				local t = now()
				for _, enc in active do
					step(enc, t)
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastWarn[player.UserId] = nil
	end)
end

function EncounterService.init(worldFolder: Folder)
	container = Instance.new("Folder")
	container.Name = "Creatures"
	container.Parent = worldFolder
end

return EncounterService
