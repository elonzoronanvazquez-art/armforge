--!strict
-- Creature health from design intent instead of a guessed multiplier. A creature declares which arm (at which upgrade level) a
-- player is expected to bring and for how many seconds of full-uptime punching the fight is worth; its maxHp is that arm's
-- damage per second times those seconds. Because it is computed from the same combat maths the players use, creatures stay in
-- step when arms are retuned, and the encounter balance simulation can check the resulting fight lengths.

local Config = script.Parent.Parent.Config
local Creatures = require(Config.Creatures)
local Combat = require(script.Parent.Combat)
local DataSchema = require(script.Parent.DataSchema)

local CreatureStats = {}

-- Expected damage per second of an arm at an upgrade level (no skills, traits or training; crits averaged in).
function CreatureStats.referenceDps(armId: string, level: number): number
	local data = DataSchema.default()
	data.arms.owned[armId] = true
	data.arms.levels[armId] = level
	data.arms.equipped = armId
	local stats = Combat.stats(data, Combat.newState(armId), 0)
	return stats.power * (1 + stats.critChance * (stats.critMult - 1)) / stats.cooldown
end

function CreatureStats.maxHp(def: Creatures.CreatureDef): number
	return math.max(1, math.floor(CreatureStats.referenceDps(def.fight.arm, def.fight.level) * def.fight.seconds))
end

return CreatureStats
