--!strict
-- STUDIO-ONLY development helpers. Every function is a no-op outside Studio (RunService:IsStudio() is false in
-- live servers), so none of this can reach the production experience. Use from the Studio command bar / MCP:
--   local D = require(game.ServerScriptService.Armforge.Dev.DevTools)
--   D.coins(D.player(), 5000); D.level(D.player(), 12); D.giveArm(D.player(), "Alloy"); D.unlockAll(D.player())

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local Game = require(Shared.Config.Game)
local Arms = require(Shared.Config.Arms)
local Islands = require(Shared.Config.Islands)
local Formulas = require(Shared.Logic.Formulas)
local Combat = require(Shared.Logic.Combat)
local Boosters = require(Shared.Logic.Boosters)
local BoosterConfig = require(Shared.Config.Boosters)
local Sessions = require(script.Parent.Parent.Services.Sessions)
local Sync = require(script.Parent.Parent.Services.Sync)
local ArmService = require(script.Parent.Parent.Services.ArmService)
local DataService = require(script.Parent.Parent.Services.DataService)
local ProgressService = require(script.Parent.Parent.Services.ProgressService)
local RockService = require(script.Parent.Parent.Services.RockService)
local EncounterService = require(script.Parent.Parent.Services.EncounterService)
local TramService = require(script.Parent.Parent.Services.TramService)
local FishingService = require(script.Parent.Parent.Services.FishingService)
local VineService = require(script.Parent.Parent.Services.VineService)
local ZoneService = require(script.Parent.Parent.Services.ZoneService)
local Tram = require(Shared.Logic.Tram)
local Momentum = require(Shared.Logic.Momentum)
local CreatureSim = require(Shared.Logic.CreatureSim)
local CreatureConfig = require(Shared.Config.Creatures)
local CreatureBuilder = require(script.Parent.Parent.World.CreatureBuilder)

local DevTools = {}

local enabled = RunService:IsStudio()

local function session(player: Player?): Sessions.Session?
	if not enabled or not player then
		return nil
	end
	return Sessions.ready(player)
end

function DevTools.enabled(): boolean
	return enabled
end

function DevTools.player(index: number?): Player?
	return Players:GetPlayers()[index or 1]
end

function DevTools.coins(player: Player?, amount: number)
	local s = session(player)
	if s and player then
		s.data.coins += amount
		Sync.now(player)
	end
end

function DevTools.shards(player: Player?, amount: number)
	local s = session(player)
	if s and player then
		s.data.shards += amount
		Sync.now(player)
	end
end

function DevTools.xp(player: Player?, amount: number)
	local s = session(player)
	if s and player then
		ProgressService.addXp(player, amount)
		Sync.now(player)
	end
end

function DevTools.level(player: Player?, level: number)
	local s = session(player)
	if s and player then
		local need = Formulas.totalXpForLevel(level) - Formulas.totalXpForLevel(s.data.level) - s.data.xp
		if need > 0 then
			ProgressService.addXp(player, need)
		end
		Sync.now(player)
	end
end

function DevTools.giveArm(player: Player?, armId: string)
	local s = session(player)
	if s and player and Arms.Defs[armId] then
		s.data.arms.owned[armId] = true
		s.data.arms.levels[armId] = s.data.arms.levels[armId] or 0
		Sync.now(player)
	end
end

function DevTools.unlockAll(player: Player?)
	local s = session(player)
	if s and player then
		for id, def in Islands.Defs do
			if not def.comingSoon then
				s.data.islands.unlocked[id] = true
			end
		end
		for id in Arms.Defs do
			s.data.arms.owned[id] = true
			s.data.arms.levels[id] = s.data.arms.levels[id] or 0
		end
		Sync.now(player)
	end
end

function DevTools.rebirths(player: Player?, n: number)
	local s = session(player)
	if s and player then
		s.data.rebirths = n
		ProgressService.updateLeaderstats(player)
		Sync.now(player)
	end
end

-- Marks an (unlocked) island as the player's current one, as Travel would, without moving them (HUD / boost checks).
function DevTools.setIsland(player: Player?, id: string)
	local s = session(player)
	if s and player and Islands.Defs[id] then
		s.data.islands.unlocked[id] = true
		s.data.islands.current = id
		Sync.now(player)
	end
end

function DevTools.booster(player: Player?, id: string, count: number?)
	local s = session(player)
	if s and player and BoosterConfig.Defs[id] then
		Boosters.give(s.data, id, count or 1)
		Sync.now(player)
	end
end

function DevTools.tp(player: Player?, pos: Vector3)
	local char = player and player.Character
	if char and enabled then
		char:PivotTo(CFrame.new(pos))
	end
end

function DevTools.rocks(): { [number]: any }
	return RockService.all()
end

function DevTools.state(player: Player?): any
	local s = session(player)
	return s and s.data
end

function DevTools.equip(player: Player?, armId: string)
	local s = session(player)
	if s and player then
		ArmService.equip(player, armId)
	end
end

-- Teleports the player next to the nearest alive rock of a type (default Granite on the start island).
function DevTools.tpToRock(player: Player?, defId: string?, island: string?): any
	local best: any = nil
	local char = player and player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local origin = if hrp then hrp.Position else Vector3.zero
	for _, e in RockService.all() do
		if e.def.id == (defId or "Granite") and e.island == (island or "Forgeheart") and e.state.alive then
			if not best or (e.center - origin).Magnitude < (best.center - origin).Magnitude then
				best = e
			end
		end
	end
	if best then
		DevTools.tp(player, best.center + Vector3.new(0, 3, best.state.layout.radius + 4))
		return { id = best.id, pos = best.center, hp = best.state.hp }
	end
	return nil
end

-- The creature released from a rock: lifecycle state, health, armor / core status.
function DevTools.encounter(id: number): any
	local enc = EncounterService.get(id)
	if not enc then
		return nil
	end
	local sim = enc.sim
	local status = if sim then CreatureSim.status(sim, os.clock()) else nil
	return {
		creature = enc.def.name,
		tier = enc.def.tier,
		state = enc.sm.state,
		spawns = enc.sm.spawns,
		rewards = enc.sm.rewards,
		simState = if sim then sim.state else nil,
		hp = if sim then math.floor(sim.hp) else nil,
		maxHp = if sim then sim.maxHp else nil,
		phase = if sim then sim.phase else nil,
		armored = if status then status.armored else nil,
		armorOpen = if status then status.armorOpen else nil,
		coreOpen = if status then status.coreOpen else nil,
		x = if sim then sim.pos.X else nil,
		z = if sim then sim.pos.Z else nil,
		attack = if sim and sim.attack then sim.attack.id else nil,
	}
end

-- Visual showcase (Studio only): builds a creature body WITHOUT a rock or a fight so its look and animation can be inspected.
local showcaseCount = 0
local function showcaseFolder(): Folder
	local f = workspace:FindFirstChild("ShowcaseCreatures")
	if not f then
		f = Instance.new("Folder")
		f.Name = "ShowcaseCreatures"
		f.Parent = workspace
	end
	return f :: Folder
end

function DevTools.showcase(defId: string, x: number, y: number, z: number, yawDeg: number?): number
	local def = CreatureConfig.Defs[defId]
	if not (enabled and def) then
		return 0
	end
	showcaseCount += 1
	local id = 90000 + showcaseCount
	local model = CreatureBuilder.build(def, id, Vector3.new(x, y, z))
	model:PivotTo(CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(yawDeg or 0), 0))
	model:SetAttribute("RockId", id)
	model:SetAttribute("CreatureId", def.id)
	model:SetAttribute("Radius", def.radius)
	model:SetAttribute("Height", def.height)
	model:SetAttribute("Tier", def.tier)
	model:SetAttribute("Name", def.name)
	model:SetAttribute("Hp", 100)
	model:SetAttribute("MaxHp", 100)
	model:SetAttribute("Alive", false) -- never a combat target
	model:SetAttribute("State", "IDLE")
	model:SetAttribute("StateStart", workspace:GetServerTimeNow())
	model:SetAttribute("StateEnd", workspace:GetServerTimeNow())
	model:SetAttribute("Phase", 1)
	model.Parent = showcaseFolder()
	CreatureBuilder.tag(model)
	return id
end

-- Puts every showcase creature (or the one with `id`) into a state for `seconds`; kind is the attack shape (circle / cone / line).
function DevTools.showcaseState(state: string, kind: string?, seconds: number?, id: number?)
	local now = workspace:GetServerTimeNow()
	for _, model in showcaseFolder():GetChildren() do
		if model:IsA("Model") and (id == nil or model:GetAttribute("RockId") == id) then
			model:SetAttribute("AttackKind", kind or "")
			model:SetAttribute("StateStart", now)
			model:SetAttribute("StateEnd", now + (seconds or 1.5))
			model:SetAttribute("State", state)
		end
	end
end

function DevTools.clearShowcase()
	showcaseFolder():ClearAllChildren()
end

-- Teleports next to the island's guardian seal.
function DevTools.tpToSeal(player: Player?, island: string): any
	for _, e in RockService.all() do
		if e.island == island and e.def.size == "seal" then
			DevTools.tp(player, e.center + Vector3.new(0, 3, e.state.layout.radius + 6))
			return { id = e.id, alive = e.state.alive }
		end
	end
	return nil
end

-- Damages the creature of rock `id` as the local player (optionally through a skill, which is what breaks armor).
function DevTools.hitCreature(player: Player?, id: number, damage: number, skill: string?): any
	local enc = EncounterService.targetFor(id)
	if not (enc and player) then
		return "no creature"
	end
	local r = EncounterService.hit(enc, player, damage, { skill = skill })
	return if r then { applied = r.applied, killed = r.killed, armored = r.armored, armorBroken = r.armorBroken, core = r.coreHit } else "refused"
end

function DevTools.rockInfo(id: number): any
	local e = RockService.get(id)
	if not e then
		return nil
	end
	return {
		hp = e.state.hp,
		maxHp = e.state.maxHp,
		stage = e.state.stage,
		alive = e.state.alive,
		removed = e.state.removedCount,
		removable = e.state.layout.removable,
		generation = e.state.generation,
		paid = e.state.paid,
		chunks = (function()
			local n = 0
			for _ in e.chunks do
				n += 1
			end
			return n
		end)(),
	}
end

-- Cross-VM bridge: the Studio command bar / MCP runs in a different Lua VM, so it cannot require() this module and see
-- live state. It invokes this BindableFunction instead:  game.ServerStorage.ArmforgeDev:Invoke("coins", 500)
local COMMANDS: { [string]: (...any) -> any } = {
	coins = function(n: number)
		DevTools.coins(DevTools.player(), n)
		return "ok"
	end,
	shards = function(n: number)
		DevTools.shards(DevTools.player(), n)
		return "ok"
	end,
	xp = function(n: number)
		DevTools.xp(DevTools.player(), n)
		return "ok"
	end,
	level = function(n: number)
		DevTools.level(DevTools.player(), n)
		return "ok"
	end,
	giveArm = function(id: string)
		DevTools.giveArm(DevTools.player(), id)
		return "ok"
	end,
	equip = function(id: string)
		DevTools.equip(DevTools.player(), id)
		return "ok"
	end,
	unlockAll = function()
		DevTools.unlockAll(DevTools.player())
		return "ok"
	end,
	rebirths = function(n: number)
		DevTools.rebirths(DevTools.player(), n)
		return "ok"
	end,
	booster = function(id: string, n: number?)
		DevTools.booster(DevTools.player(), id, n)
		return "ok"
	end,
	-- Presses a tram station's prompt for the local player ("base" | "summit").
	ride = function(station: string)
		local player = DevTools.player()
		if not player then
			return "no player"
		end
		return TramService.board(player, station, Tram.state(workspace:GetServerTimeNow()))
	end,
	tramState = function()
		local st = Tram.state(workspace:GetServerTimeNow())
		return { docked = st.docked, leg = st.leg, cabin1 = st.cabin1, cabin2 = st.cabin2, departsIn = st.departsIn, riders = TramService.riderCount() }
	end,
	-- Fishing / vines with a fixed roll (0 = the first fish and always lucky, 0.99 = never lucky), then the normal luck again.
	fish = function(luck: number)
		local player = DevTools.player()
		if not player then
			return "no player"
		end
		FishingService.setRng({ next = function() return luck end, range = function(_, lo: number) return lo end })
		return FishingService.trigger(player, os.clock())
	end,
	vine = function(luck: number)
		local player = DevTools.player()
		local vine = game:GetService("CollectionService"):GetTagged("SwingVine")[1]
		if not (player and vine and vine:IsA("BasePart")) then
			return "no player or vine"
		end
		VineService.setRng({ next = function() return luck end, range = function(_, lo: number) return lo end })
		return VineService.swing(player, vine, os.clock())
	end,
	gift = function()
		local player = DevTools.player()
		return if player then VineService.gift(player, os.clock()) else "no player"
	end,
	zone = function()
		local player = DevTools.player()
		return ZoneService.current(player :: Player) or "none"
	end,
	momentum = function()
		local s = session(DevTools.player())
		return if s then Momentum.remaining(s, os.clock()) else -1
	end,
	island = function(id: string)
		DevTools.setIsland(DevTools.player(), id)
		return "ok"
	end,
	tpToRock = function(defId: string?, island: string?)
		return DevTools.tpToRock(DevTools.player(), defId, island)
	end,
	tp = function(x: number, y: number, z: number)
		DevTools.tp(DevTools.player(), Vector3.new(x, y, z))
		return "ok"
	end,
	encounter = function(id: number)
		return DevTools.encounter(id)
	end,
	showcase = function(defId: string, x: number, y: number, z: number, yaw: number?)
		return DevTools.showcase(defId, x, y, z, yaw)
	end,
	showcaseState = function(state: string, kind: string?, seconds: number?, id: number?)
		DevTools.showcaseState(state, kind, seconds, id)
		return "ok"
	end,
	clearShowcase = function()
		DevTools.clearShowcase()
		return "cleared"
	end,
	tpToSeal = function(island: string)
		return DevTools.tpToSeal(DevTools.player(), island)
	end,
	hitCreature = function(id: number, damage: number, skill: string?)
		return DevTools.hitCreature(DevTools.player(), id, damage, skill)
	end,
	guardians = function()
		local s = session(DevTools.player())
		return s and s.data.guardians
	end,
	rockInfo = function(id: number)
		return DevTools.rockInfo(id)
	end,
	state = function()
		local d = DevTools.state(DevTools.player())
		return d and game:GetService("HttpService"):JSONEncode(d)
	end,
	-- Live combat numbers (power, cooldown, crit) exactly as the server computes them right now.
	combatStats = function()
		local player = DevTools.player()
		local s = player and Sessions.ready(player)
		if not s then
			return "no session"
		end
		local now = os.clock()
		Combat.updateBuffs(s.combat, now)
		local st = Combat.stats(s.data, s.combat, now)
		return { power = st.power, cooldown = st.cooldown, crit = st.critChance, haste = st.haste, arm = st.armId, combo = s.combat.combo, overclock = s.combat.overclock }
	end,
	hrp = function()
		local p = DevTools.player()
		local hrp = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		return hrp and tostring(hrp.Position)
	end,
	-- Applies authoritative damage to a rock as the local player (fires the same effects as a real strike).
	hitRock = function(id: number, damage: number, crit: boolean?)
		local player = DevTools.player()
		local entry = RockService.get(id)
		if not (player and entry) then
			return "no rock"
		end
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local dir = if hrp then (hrp.Position - entry.center).Unit else Vector3.new(0, 0, 1)
		local result = RockService.damage(entry, player, player.UserId, damage, {
			hitDir = dir,
			power = 1,
			crit = crit == true,
			hitPos = entry.center + dir * entry.state.layout.radius * 0.9,
		})
		return result and { hp = result.hp, stage = result.stage, removed = #result.removed, killed = result.killed } or "ignored"
	end,
	-- Simulates two different players damaging one rock; returns how many reward callbacks fired (must be 1 per contributor).
	contend = function(defId: string)
		local entry = RockService.spawnAt(defId, Vector3.new(0, 0.6, 140))
		local calls = 0
		local half = entry.state.maxHp / 2
		RockService.damage(entry, nil, 900001, half, { hitDir = Vector3.zAxis })
		RockService.damage(entry, nil, 900002, half + 5, { hitDir = Vector3.zAxis })
		local again = RockService.damage(entry, nil, 900001, 999, { hitDir = Vector3.zAxis })
		for _ in entry.state.contributors do
			calls += 1
		end
		return { contributors = calls, paid = entry.state.paid, alive = entry.state.alive, secondKill = again ~= nil }
	end,
	spawnRock = function(defId: string, x: number, y: number, z: number)
		return RockService.spawnAt(defId, Vector3.new(x, y, z)).id
	end,
	-- The next n DataStore operations fail (persistence failure drills against the real store; Studio only).
	failStore = function(n: number)
		DataService.injectFailures(n)
		return `next {n} DataStore operations will fail`
	end,
	-- Times the per-strike server scans (microseconds per call) at the local player's position.
	--   playerScan mirrors the player loop inside RockService.fxNear (every strike, hit and break pays for it).
	bench = function(iterations: number?)
		local n = math.clamp(iterations or 2000, 10, 20000)
		local player = DevTools.player()
		local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local pos = if root then root.Position else Vector3.zero
		local function micros(fn: () -> ()): number
			local t0 = os.clock()
			for _ = 1, n do
				fn()
			end
			return math.floor((os.clock() - t0) * 1e6 / n * 100) / 100
		end
		local rockCount = 0
		for _ in RockService.all() do
			rockCount += 1
		end
		local found = 0
		local r2 = Game.Combat.fxRadius ^ 2
		return {
			rocks = rockCount,
			players = #Players:GetPlayers(),
			iterations = n,
			nearMicros = micros(function()
				found = #RockService.near(pos, 30)
			end),
			nearFound = found,
			playerScanMicros = micros(function()
				local reached = 0
				for _, p in Players:GetPlayers() do
					local char = p.Character
					local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
					if hrp and (hrp.Position - pos).Magnitude ^ 2 <= r2 then
						reached += 1
					end
				end
			end),
		}
	end,
}

function DevTools.init()
	if not enabled then
		return
	end
	print("[ARMFORGE] DevTools enabled (Studio only)")
	local ServerStorage = game:GetService("ServerStorage")
	local bridge = Instance.new("BindableFunction")
	bridge.Name = "ArmforgeDev"
	bridge.OnInvoke = function(cmd: string, ...: any)
		local fn = COMMANDS[cmd]
		if not fn then
			return "unknown command " .. tostring(cmd)
		end
		local ok, result = pcall(fn, ...)
		if not ok then
			return "error: " .. tostring(result)
		end
		return result
	end
	bridge.Parent = ServerStorage
end

return DevTools
