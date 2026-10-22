--!strict
-- Skill learning (skill points), cooldowns and per-rank effect numbers.

local Config = script.Parent.Parent.Config
local SkillConfig = require(Config.Skills)
local Arms = require(Config.Arms)
local Formulas = require(script.Parent.Formulas)

local Skills = {}

function Skills.rank(data: any, id: string): number
	return data.skills.ranks[id] or 0
end

function Skills.learned(data: any, id: string): boolean
	return Skills.rank(data, id) >= 1
end

-- Spends skill points to learn (rank 1) or improve a skill.
function Skills.rankUp(data: any, id: string): { ok: boolean, err: string?, rank: number? }
	local def = SkillConfig.Defs[id]
	if not def then
		return { ok = false, err = "unknown_skill" }
	end
	if data.level < def.unlockLevel then
		return { ok = false, err = "level" }
	end
	local rank = Skills.rank(data, id)
	if rank >= def.maxRank then
		return { ok = false, err = "max_rank" }
	end
	local cost = def.rankCost[rank + 1]
	if data.skillPoints < cost then
		return { ok = false, err = "skill_points" }
	end
	data.skillPoints -= cost
	data.skills.ranks[id] = rank + 1
	return { ok = true, rank = rank + 1 }
end

-- Cooldown in seconds after Endurance training.
function Skills.cooldown(data: any, id: string): number
	local def = SkillConfig.Defs[id]
	local reduction = math.min(0.5, Formulas.trainingStatBonus({ endurance = data.training.endurance.level }, "endurance"))
	return def.cooldown * (1 - reduction)
end

function Skills.affinity(armId: string, id: string): number
	local arm = Arms.Defs[armId]
	return if arm then (arm.affinity[id] or 0) else 0
end

local function at(list: { number }, rank: number): number
	return list[math.clamp(rank, 1, #list)]
end

-- Numeric effect of a skill at a rank, including the equipped arm's affinity.
function Skills.effect(id: string, rank: number, armId: string): { [string]: number }
	local fx = SkillConfig.Effects[id] :: any
	local boost = 1 + Skills.affinity(armId, id)
	if id == "ChargedSmash" then
		return { damageMult = at(fx.damageMult, rank) * boost, windup = fx.windup, minChunks = fx.minChunks }
	elseif id == "CriticalFocus" then
		return { critBonus = at(fx.critBonus, rank), duration = at(fx.duration, rank) * boost }
	elseif id == "Overdrive" then
		return {
			hasteBonus = at(fx.hasteBonus, rank),
			powerBonus = at(fx.powerBonus, rank),
			duration = at(fx.duration, rank) * boost,
			overheatDuration = fx.overheat.duration,
			overheatPenalty = fx.overheat.hastePenalty,
		}
	elseif id == "ShatterWave" then
		return {
			damageMult = at(fx.damageMult, rank) * boost,
			radius = at(fx.radius, rank),
			maxTargets = fx.maxTargets,
		}
	end
	return {}
end

return Skills
