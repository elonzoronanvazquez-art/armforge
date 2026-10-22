--!strict
-- STUDIO-ONLY development helpers. Every function is a no-op outside Studio (RunService:IsStudio() is false in
-- live servers), so none of this can reach the production experience. Use from the Studio command bar / MCP:
--   local D = require(game.ServerScriptService.Armforge.Dev.DevTools)
--   D.coins(D.player(), 5000); D.level(D.player(), 12); D.giveArm(D.player(), "Alloy"); D.unlockAll(D.player())

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local Arms = require(Shared.Config.Arms)
local Islands = require(Shared.Config.Islands)
local Formulas = require(Shared.Logic.Formulas)
local Boosters = require(Shared.Logic.Boosters)
local BoosterConfig = require(Shared.Config.Boosters)
local Sessions = require(script.Parent.Parent.Services.Sessions)
local Sync = require(script.Parent.Parent.Services.Sync)
local ArmService = require(script.Parent.Parent.Services.ArmService)
local ProgressService = require(script.Parent.Parent.Services.ProgressService)
local RockService = require(script.Parent.Parent.Services.RockService)

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
	tpToRock = function(defId: string?, island: string?)
		return DevTools.tpToRock(DevTools.player(), defId, island)
	end,
	tp = function(x: number, y: number, z: number)
		DevTools.tp(DevTools.player(), Vector3.new(x, y, z))
		return "ok"
	end,
	rockInfo = function(id: number)
		return DevTools.rockInfo(id)
	end,
	state = function()
		local d = DevTools.state(DevTools.player())
		return d and game:GetService("HttpService"):JSONEncode(d)
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
