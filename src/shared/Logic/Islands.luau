--!strict
-- Island access. The server is authoritative; the UI uses the same function to show requirements.

local IslandConfig = require(script.Parent.Parent.Config.Islands)

local Islands = {}

export type Status = { unlocked: boolean, canUnlock: boolean, missing: { string }, comingSoon: boolean }

export type Requirement = { text: string, met: boolean }

-- Every requirement for entering this island with whether it is met. The guardian gate is TWO separate lines: the rebirths and
-- the previous island's guardian victory, so neither can stand in for the other (and the UI can show each).
function Islands.requirements(data: any, islandId: string): { Requirement }
	local def = IslandConfig.Defs[islandId]
	local out: { Requirement } = {}
	if not def then
		table.insert(out, { text = "unknown_island", met = false })
		return out
	end
	local req = def.requires
	if req.level then
		table.insert(out, { text = `Level {req.level}`, met = data.level >= req.level })
	end
	if req.rebirths then
		table.insert(out, { text = `Rebirth {req.rebirths}`, met = data.rebirths >= req.rebirths })
	end
	if req.coins then
		table.insert(out, { text = `{req.coins} coins`, met = data.coins >= req.coins })
	end
	local previous: string? = nil
	for i, id in IslandConfig.Order do
		if id == islandId then
			previous = IslandConfig.Order[i - 1]
		end
	end
	local guard = previous and IslandConfig.Defs[previous].guardian
	if previous and guard then
		table.insert(out, { text = `Rebirth {guard.rebirths}`, met = data.rebirths >= guard.rebirths })
		table.insert(out, { text = `Defeat the guardian of {IslandConfig.Defs[previous].name}`, met = data.guardians ~= nil and data.guardians.defeated[previous] == true })
	end
	return out
end

-- Which requirements the player is missing for this island (empty = may unlock).
function Islands.missing(data: any, islandId: string): { string }
	local out: { string } = {}
	for _, r in Islands.requirements(data, islandId) do
		if not r.met then
			table.insert(out, r.text)
		end
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
