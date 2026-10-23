--!strict
-- Island access. The server is authoritative; the UI uses the same function to show requirements.

local IslandConfig = require(script.Parent.Parent.Config.Islands)

local Islands = {}

export type Status = { unlocked: boolean, canUnlock: boolean, missing: { string }, comingSoon: boolean }

-- Which requirements the player is missing for this island (empty = may unlock).
function Islands.missing(data: any, islandId: string): { string }
	local def = IslandConfig.Defs[islandId]
	local out: { string } = {}
	if not def then
		table.insert(out, "unknown_island")
		return out
	end
	local req = def.requires
	if req.level and data.level < req.level then
		table.insert(out, `Level {req.level}`)
	end
	if req.rebirths and data.rebirths < req.rebirths then
		table.insert(out, `Rebirth {req.rebirths}`)
	end
	if req.coins and data.coins < req.coins then
		table.insert(out, `{req.coins} coins`)
	end
	return out
end

function Islands.status(data: any, islandId: string): Status
	local def = IslandConfig.Defs[islandId]
	local missing = Islands.missing(data, islandId)
	local coming = def ~= nil and def.comingSoon == true
	return {
		unlocked = data.islands.unlocked[islandId] == true,
		canUnlock = #missing == 0 and not coming,
		missing = missing,
		comingSoon = coming,
	}
end

function Islands.unlock(data: any, islandId: string): { ok: boolean, err: string? }
	local def = IslandConfig.Defs[islandId]
	if not def then
		return { ok = false, err = "unknown_island" }
	end
	if def.comingSoon then
		return { ok = false, err = "coming_soon" }
	end
	if data.islands.unlocked[islandId] then
		return { ok = true }
	end
	if #Islands.missing(data, islandId) > 0 then
		return { ok = false, err = "requirements" }
	end
	if def.requires.coins then
		data.coins -= def.requires.coins
	end
	data.islands.unlocked[islandId] = true
	return { ok = true }
end

-- May the player be on / travel to this island right now?
function Islands.canTravel(data: any, islandId: string): { ok: boolean, err: string? }
	local def = IslandConfig.Defs[islandId]
	if not def then
		return { ok = false, err = "unknown_island" }
	end
	if def.comingSoon then
		return { ok = false, err = "coming_soon" }
	end
	if not data.islands.unlocked[islandId] then
		return { ok = false, err = "locked" }
	end
	return { ok = true }
end

return Islands
