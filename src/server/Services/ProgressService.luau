--!strict
-- Grants rewards (coins / XP / shards), runs level-ups, and tells clients. All reward maths goes through
-- shared/Logic (Formulas + Progression) so it stays testable; this module only applies results to live sessions.

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local Net = require(Shared.Net)
local Game = require(Shared.Config.Game)
local Formulas = require(Shared.Logic.Formulas)
local Progression = require(Shared.Logic.Progression)
local Sessions = require(script.Parent.Sessions)
local Sync = require(script.Parent.Sync)

local ProgressService = {}

local remotes: Net.Remotes

function ProgressService.init()
	remotes = Net.server()
end

local function devMultiplier(): number
	if RunService:IsStudio() and Game.Dev.progressionMultiplier > 1 then
		return Game.Dev.progressionMultiplier
	end
	return 1
end

function ProgressService.notify(player: Player, kind: string, payload: any)
	remotes.Notify:FireClient(player, kind, payload)
end

function ProgressService.updateLeaderstats(player: Player)
	local s = Sessions.get(player)
	local data = s and s.data
	local stats = player:FindFirstChild("leaderstats")
	if not (data and stats) then
		return
	end
	local level = stats:FindFirstChild("Level") :: IntValue?
	local rebirths = stats:FindFirstChild("Rebirths") :: IntValue?
	if level then
		level.Value = data.level
	end
	if rebirths then
		rebirths.Value = data.rebirths
	end
end

local function announceLevelUps(player: Player, result: Progression.XpResult)
	if result.levelsGained > 0 then
		ProgressService.notify(player, "LevelUp", { level = result.level, rewards = result.rewards })
		ProgressService.updateLeaderstats(player)
	end
end

-- Adds XP with the player's multiplier already applied by the caller.
function ProgressService.addXp(player: Player, amount: number)
	local s = Sessions.ready(player)
	if not s then
		return
	end
	local result = Progression.addXp(s.data, amount)
	announceLevelUps(player, result)
	Sync.mark(player)
end

-- Called by RockService once per contributor when a rock is destroyed.
function ProgressService.rockReward(player: Player, reward: any, entry: any)
	local s = Sessions.ready(player)
	if not s then
		return
	end
	local data = s.data
	local mult = devMultiplier()
	local coins = math.floor(reward.coins * Formulas.coinMultiplier(data, data.arms.equipped) * mult)
	local xp = math.floor(reward.xp * Formulas.xpMultiplier(data) * mult)
	local shards = reward.shards
	if coins <= 0 and xp <= 0 and shards <= 0 then
		return
	end
	data.coins += coins
	data.shards += shards
	data.stats.rocksDestroyed += 1
	local result = Progression.addXp(data, xp)
	Progression.markTutorial(data, "destroyed")
	ProgressService.notify(player, "Reward", {
		coins = coins,
		xp = xp,
		shards = shards,
		pos = entry.center,
		rock = entry.def.name,
		rare = entry.def.rare,
		killer = reward.killer,
		id = entry.id,
	})
	announceLevelUps(player, result)
	Sync.mark(player)
end

return ProgressService
