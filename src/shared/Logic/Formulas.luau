--!strict
-- Every balance formula in one place. Pure functions of config + player data; no Roblox APIs.

local Config = script.Parent.Parent.Config
local Arms = require(Config.Arms)
local Progression = require(Config.Progression)
local Training = require(Config.Training)
local Game = require(Config.Game)
local Boosters = require(Config.Boosters)

local Formulas = {}

local function pow(a: number, b: number): number
	return a ^ b
end

-- XP needed to go from `level` to `level + 1`.
function Formulas.xpToNext(level: number): number
	return math.floor(Progression.XpBase + Progression.XpCoef * pow(level, Progression.XpExp))
end

-- Total XP to reach `level` from level 1.
function Formulas.totalXpForLevel(level: number): number
	local total = 0
	for l = 1, level - 1 do
		total += Formulas.xpToNext(l)
	end
	return total
end

function Formulas.armPower(armId: string, level: number): number
	local def = Arms.Defs[armId]
	return def.basePower * pow(def.growth, level)
end

-- Price of upgrading an arm from `level` to `level + 1` (nil at max level).
function Formulas.upgradeCost(armId: string, level: number): number?
	local def = Arms.Defs[armId]
	if level >= def.maxLevel then
		return nil
	end
	return math.floor(def.upgradeBaseCost * pow(def.upgradeGrowth, level) + 0.5)
end

-- Training points to go from stat level L to L + 1.
function Formulas.trainingPointsToNext(level: number): number
	return math.floor(Training.PointsBase + Training.PointsCoef * pow(level, Training.PointsExp))
end

-- Highest stat level the player may reach right now.
function Formulas.trainingLevelCap(stat: string, playerLevel: number): number
	local maxLevel = Training.Stats[stat].maxLevel
	return math.min(maxLevel, Training.LevelCapBase + Training.LevelCapPerPlayerLevel * playerLevel)
end

function Formulas.rebirthCost(rebirths: number): number
	return math.floor(Progression.Rebirth.baseCoinCost * pow(Progression.Rebirth.costGrowth, rebirths))
end

-- Permanent additive bonuses earned from rebirths.
function Formulas.rebirthBonus(rebirths: number, stat: string): number
	local per = (Progression.Rebirth.bonusPerRebirth :: any)[stat] or 0
	return per * rebirths
end

function Formulas.trainingStatBonus(trainingLevels: { [string]: number }, stat: string): number
	local lvl = trainingLevels[stat] or 0
	return lvl * Training.Stats[stat].perLevel
end

-- Sum of active booster bonuses for one stat, capped per stat.
function Formulas.boosterBonus(active: { [string]: number }, stat: string): number
	local total = 0
	for id, remaining in active do
		local def = Boosters.Defs[id]
		if def and def.stat == stat and remaining > 0 then
			total += def.bonus
		end
	end
	local cap = Boosters.StatCap[stat] or math.huge
	return math.min(total, cap)
end

-- Coin multiplier = 1 + rebirth + booster + arm bonus (all additive).
function Formulas.coinMultiplier(data: any, armId: string): number
	local arm = Arms.Defs[armId]
	return 1
		+ Formulas.rebirthBonus(data.rebirths, "coins")
		+ Formulas.boosterBonus(data.boosters.active, "coins")
		+ (arm and arm.coinBonus or 0)
end

function Formulas.xpMultiplier(data: any): number
	return 1 + Formulas.rebirthBonus(data.rebirths, "xp") + Formulas.boosterBonus(data.boosters.active, "xp")
end

function Formulas.trainingMultiplier(data: any): number
	return 1
		+ Formulas.rebirthBonus(data.rebirths, "training")
		+ Formulas.boosterBonus(data.boosters.active, "training")
end

-- Clamp helper used by combat.
function Formulas.clampHaste(haste: number): number
	return math.clamp(haste, -0.9, Game.Combat.maxHasteBonus)
end

return Formulas
