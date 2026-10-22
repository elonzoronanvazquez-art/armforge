--!strict
-- Booster inventory, activation and timers. Rules (see Config/Boosters): re-activating extends the timer up to the
-- booster's maximum, bonuses of the same stat add up and are capped per stat, timers tick only while in-game.

local Config = script.Parent.Parent.Config
local BoosterConfig = require(Config.Boosters)
local Formulas = require(script.Parent.Formulas)

local Boosters = {}

export type Result = { ok: boolean, err: string?, remaining: number? }

function Boosters.give(data: any, id: string, count: number)
	if not BoosterConfig.Defs[id] or count <= 0 then
		return
	end
	data.boosters.inventory[id] = math.min(999, (data.boosters.inventory[id] or 0) + count)
end

function Boosters.activate(data: any, id: string): Result
	local def = BoosterConfig.Defs[id]
	if not def then
		return { ok = false, err = "unknown_booster" }
	end
	if (data.boosters.inventory[id] or 0) < 1 then
		return { ok = false, err = "none_left" }
	end
	local current = data.boosters.active[id] or 0
	if current >= def.maxDuration - 0.001 then
		return { ok = false, err = "max_duration" }
	end
	data.boosters.inventory[id] -= 1
	if data.boosters.inventory[id] <= 0 then
		data.boosters.inventory[id] = nil
	end
	local remaining = math.min(def.maxDuration, current + def.duration)
	data.boosters.active[id] = remaining
	return { ok = true, remaining = remaining }
end

-- Advances all running timers by dt seconds. Returns the ids that expired.
function Boosters.tick(data: any, dt: number): { string }
	local expired = {}
	for id, remaining in data.boosters.active do
		local left = remaining - dt
		if left <= 0 then
			data.boosters.active[id] = nil
			table.insert(expired, id)
		else
			data.boosters.active[id] = left
		end
	end
	return expired
end

function Boosters.bonus(data: any, stat: string): number
	return Formulas.boosterBonus(data.boosters.active, stat)
end

return Boosters
