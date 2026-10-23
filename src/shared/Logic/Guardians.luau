--!strict
-- Island guardians: eligibility, victory records and the two-part island gate. Pure and server-authoritative; the UI mirrors it.
--
-- Rules (all checked independently, never inferred from one another):
--   * A guardian can only be fought by a player with at least `guardian.rebirths` rebirths AND access to its island.
--   * A victory is recorded per player in data.guardians.defeated[islandId] (and mirrored in data.islands.completed).
--   * The NEXT island needs the previous island's guardian defeated AND that guardian's rebirth count, on top of its own
--     level requirement. Rebirthing never defeats a guardian; defeating one never grants rebirths.

local Config = script.Parent.Parent.Config
local IslandConfig = require(Config.Islands)
local Creatures = require(Config.Creatures)

local Guardians = {}

export type Gate = {
	island: string,
	guardianName: string,
	state: string, -- rebirth_needed | ready | defeated | no_guardian
	rebirthsNeeded: number,
	rebirthsHave: number,
	defeated: boolean,
	next: string?, -- the island this guardian gates
	nextState: string, -- none | locked | available | unlocked
	nextMissing: { string },
}

function Guardians.of(islandId: string): IslandConfig.GuardianDef?
	local def = IslandConfig.Defs[islandId]
	return if def then def.guardian else nil
end

function Guardians.defeated(data: any, islandId: string): boolean
	return data.guardians ~= nil and data.guardians.defeated[islandId] == true
end

function Guardians.name(islandId: string): string
	local g = Guardians.of(islandId)
	local c = g and Creatures.Defs[g.creature]
	return if c then c.name else "the guardian"
end

-- The island that comes after this one on the ladder (the one its guardian helps open).
function Guardians.nextIsland(islandId: string): string?
	for i, id in IslandConfig.Order do
		if id == islandId then
			return IslandConfig.Order[i + 1]
		end
	end
	return nil
end

-- May this player fight this island's guardian right now? Independent of whether it was beaten before.
function Guardians.canChallenge(data: any, islandId: string): { ok: boolean, err: string?, missing: { string } }
	local missing: { string } = {}
	local g = Guardians.of(islandId)
	if not g then
		return { ok = false, err = "no_guardian", missing = missing }
	end
	if not data.islands.unlocked[islandId] then
		table.insert(missing, "Access to the island")
	end
	if data.rebirths < g.rebirths then
		table.insert(missing, `Rebirth {g.rebirths}`)
	end
	if #missing > 0 then
		return { ok = false, err = "requirements", missing = missing }
	end
	return { ok = true, missing = missing }
end

-- Records a victory over this island's guardian. Re-validates eligibility itself, so a caller can never complete an island
-- the player was not allowed to fight. first = true only for the first victory (the completion event).
function Guardians.recordDefeat(data: any, islandId: string): { ok: boolean, first: boolean, err: string? }
	local check = Guardians.canChallenge(data, islandId)
	if not check.ok then
		return { ok = false, first = false, err = check.err }
	end
	local first = not Guardians.defeated(data, islandId)
	data.guardians.defeated[islandId] = true
	data.islands.completed[islandId] = true
	if first then
		data.stats.guardianVictories += 1
	end
	return { ok = true, first = first }
end

-- The progression state the UI shows for this island's guardian and the island behind it.
function Guardians.gate(data: any, islandId: string, missingFor: (any, string) -> { string }): Gate
	local g = Guardians.of(islandId)
	local nextId = Guardians.nextIsland(islandId)
	local gate: Gate = {
		island = islandId,
		guardianName = Guardians.name(islandId),
		state = "no_guardian",
		rebirthsNeeded = if g then g.rebirths else 0,
		rebirthsHave = data.rebirths,
		defeated = Guardians.defeated(data, islandId),
		next = nextId,
		nextState = "none",
		nextMissing = {},
	}
	if not g then
		return gate
	end
	if gate.defeated then
		gate.state = "defeated"
	elseif data.rebirths < g.rebirths then
		gate.state = "rebirth_needed"
	else
		gate.state = "ready"
	end
	if nextId then
		gate.nextMissing = missingFor(data, nextId)
		if data.islands.unlocked[nextId] then
			gate.nextState = "unlocked"
		elseif #gate.nextMissing == 0 then
			gate.nextState = "available"
		else
			gate.nextState = "locked"
		end
	end
	return gate
end

return Guardians
