--!strict
-- Island access. The server is authoritative; the UI uses the same function to show requirements.

local IslandConfig = require(script.Parent.Parent.Config.Islands)

local Islands = {}

export type Status = { unlocked: boolean, canUnlock: boolean, missing: { string }, comingSoon: boolean }

export type Requirement = { text: string, met: boolean }

-- The island whose guardian gates this one: the nearest EARLIER island on the ladder that has a guardian. Islands without a guardian
-- yet (coming-soon teasers such as Cogspire) are skipped, so they never block the playable islands behind them.
function Islands.previousGuarded(islandId: string): string?
	local index = table.find(IslandConfig.Order, islandId)
	if not index then
		return nil
	end
	for i = index - 1, 1, -1 do
		local id = IslandConfig.Order[i]
		if IslandConfig.Defs[id].guardian then
			return id
		end
	end
	return nil
end

-- The island a guardian's victory helps open: the nearest LATER island that is not coming soon. On the last rung that is the
-- teaser island itself (which stays closed), so the UI can still say what is next.
function Islands.nextPlayable(islandId: string): string?
	local index = table.find(IslandConfig.Order, islandId)
	if not index then
		return nil
	end
	for i = index + 1, #IslandConfig.Order do
		local id = IslandConfig.Order[i]
		if not IslandConfig.Defs[id].comingSoon then
			return id
		end
	end
	return IslandConfig.Order[index + 1]
end

-- Reward multipliers for everything earned on this island (1 / 1 when the island has no boost).
function Islands.rewardBoost(islandId: string): { coins: number, xp: number }
	local def = IslandConfig.Defs[islandId]
	local boost = def and def.boost
	if boost then
		return { coins = boost.coins, xp = boost.xp }
	end
	return { coins = 1, xp = 1 }
end

-- A short label for the HUD / island cards ("+50% coins & XP"), nil without a boost.
function Islands.boostText(islandId: string): string?
	local def = IslandConfig.Defs[islandId]
	local boost = def and def.boost
	if not boost then
		return nil
	end
	local coins = math.floor((boost.coins - 1) * 100 + 0.5)
	local xp = math.floor((boost.xp - 1) * 100 + 0.5)
	if coins == xp then
		return `+{coins}% coins & XP`
	end
	return `+{coins}% coins, +{xp}% XP`
end

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
	local previous = Islands.previousGuarded(islandId)
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
