--!strict
-- XP / levels / rebirth / tutorial progress. Pure: mutates the PlayerData table it is given.

local Config = script.Parent.Parent.Config
local ProgressionConfig = require(Config.Progression)
local Arms = require(Config.Arms)
local Training = require(Config.Training)
local Skills = require(Config.Skills)
local Formulas = require(script.Parent.Formulas)
local Boosters = require(script.Parent.Boosters)

local Progression = {}

export type LevelReward = { level: number, coins: number, skillPoints: number, text: string?, boosters: { [string]: number }? }
export type XpResult = { gained: number, levelsGained: number, rewards: { LevelReward }, level: number }

-- Adds XP and processes any level-ups (each level grants skill points, coins and milestone rewards).
function Progression.addXp(data: any, amount: number): XpResult
	local result: XpResult = { gained = 0, levelsGained = 0, rewards = {}, level = data.level }
	if amount <= 0 or data.level >= ProgressionConfig.MaxLevel then
		return result
	end
	amount = math.floor(amount)
	result.gained = amount
	data.xp += amount
	while data.level < ProgressionConfig.MaxLevel do
		local need = Formulas.xpToNext(data.level)
		if data.xp < need then
			break
		end
		data.xp -= need
		data.level += 1
		data.skillPoints += ProgressionConfig.SkillPointsPerLevel
		local coins = ProgressionConfig.LevelUpCoins * data.level
		data.coins += coins
		local milestone = ProgressionConfig.LevelRewards[data.level]
		if milestone and milestone.boosters then
			for id, n in milestone.boosters do
				Boosters.give(data, id, n)
			end
		end
		result.levelsGained += 1
		table.insert(result.rewards, {
			level = data.level,
			coins = coins,
			skillPoints = ProgressionConfig.SkillPointsPerLevel,
			text = milestone and milestone.text,
			boosters = milestone and milestone.boosters,
		})
	end
	if data.level >= ProgressionConfig.MaxLevel then
		data.xp = 0
	end
	result.level = data.level
	return result
end

-- Rebirth ----------------------------------------------------------------------------------------------

export type RebirthStatus = {
	eligible: boolean,
	missing: { string },
	cost: number,
	nextCoinBonus: number,
	nextPowerBonus: number,
	nextXpBonus: number,
}

function Progression.rebirthStatus(data: any): RebirthStatus
	local rules = ProgressionConfig.Rebirth
	local missing: { string } = {}
	if data.rebirths >= rules.maxRebirths then
		table.insert(missing, "Max rebirths reached")
	end
	if data.level < rules.minLevel then
		table.insert(missing, `Level {rules.minLevel}`)
	end
	local cost = Formulas.rebirthCost(data.rebirths)
	if data.coins < cost then
		table.insert(missing, `{cost} coins`)
	end
	return {
		eligible = #missing == 0,
		missing = missing,
		cost = cost,
		nextCoinBonus = Formulas.rebirthBonus(data.rebirths + 1, "coins"),
		nextPowerBonus = Formulas.rebirthBonus(data.rebirths + 1, "power"),
		nextXpBonus = Formulas.rebirthBonus(data.rebirths + 1, "xp"),
	}
end

-- Applies the data-driven reset rules. Returns {ok, err}.
function Progression.rebirth(data: any): { ok: boolean, err: string?, rebirths: number? }
	local status = Progression.rebirthStatus(data)
	if not status.eligible then
		return { ok = false, err = "not_eligible" }
	end
	local rules = ProgressionConfig.Rebirth
	local resets = rules.resets
	-- Cost is paid before coins are wiped, so a rebirth never grants coins back.
	data.coins -= status.cost
	if resets.coins then
		data.coins = 0
	end
	if resets.level then
		data.level = 1
	end
	if resets.xp then
		data.xp = 0
	end
	if resets.skillPoints then
		data.skillPoints = 0
	end
	if resets.skillRanks then
		for _, id in Skills.Order do
			data.skills.ranks[id] = 0
		end
	end
	if resets.armUpgradeLevels then
		for id in data.arms.owned do
			data.arms.levels[id] = 0
		end
	end
	if resets.trainingStats then
		for _, stat in Training.StatOrder do
			data.training[stat] = { level = 0, points = 0 }
		end
	end
	data.rebirths += 1
	for id, n in rules.reward.boosters do
		Boosters.give(data, id, n)
	end
	data.shards += rules.reward.shards
	return { ok = true, rebirths = data.rebirths }
end

-- Tutorial -----------------------------------------------------------------------------------------------

-- Records a milestone flag and advances the tutorial step while the current step's flag is satisfied.
-- Returns true if the step changed.
function Progression.markTutorial(data: any, flag: string): boolean
	if data.tutorial.flags[flag] then
		return false
	end
	data.tutorial.flags[flag] = true
	local changed = false
	while true do
		local step = ProgressionConfig.Tutorial[data.tutorial.step]
		if step and data.tutorial.flags[step.flag] then
			data.tutorial.step += 1
			changed = true
		else
			break
		end
	end
	return changed
end

function Progression.tutorialDone(data: any): boolean
	return data.tutorial.step > #ProgressionConfig.Tutorial
end

return Progression
