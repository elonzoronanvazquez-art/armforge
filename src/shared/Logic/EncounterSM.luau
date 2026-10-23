--!strict
-- The lifecycle of one rock encounter, as a small checked state machine. A rock's wear (INTACT -> SURFACE -> CHIPPED ->
-- FRACTURED, owned by RockSim) is the "sealed" half; this module owns what happens once the final hit lands, and it is the only
-- thing allowed to say "a creature may exist now". Every transition is validated, every transition bumps a counter, and the
-- `token` changes whenever a new life starts, so a stale timer from a previous life can never act on the current one.
--
--   SEALED -> REVEAL -> COMBAT -> DEFEATED -> RECOVERY -> RESPAWNING -> SEALED
--                         |                       ^
--                         +-----> RECOVERY -------+      (abandoned: nobody around for a long time)

local EncounterSM = {}

export type Encounter = {
	state: string,
	token: number, -- changes on every new life (SEALED re-entered)
	transitions: number,
	spawns: number, -- creatures released over the encounter's lifetime (one per life, never two)
	rewards: number, -- creature reward events paid out
}

local ALLOWED: { [string]: { [string]: boolean } } = {
	SEALED = { REVEAL = true },
	REVEAL = { COMBAT = true, RECOVERY = true },
	COMBAT = { DEFEATED = true, RECOVERY = true },
	DEFEATED = { RECOVERY = true },
	RECOVERY = { RESPAWNING = true },
	RESPAWNING = { SEALED = true },
}

EncounterSM.States = { "SEALED", "REVEAL", "COMBAT", "DEFEATED", "RECOVERY", "RESPAWNING" }

function EncounterSM.new(): Encounter
	return { state = "SEALED", token = 1, transitions = 0, spawns = 0, rewards = 0 }
end

function EncounterSM.can(enc: Encounter, to: string): boolean
	local row = ALLOWED[enc.state]
	return row ~= nil and row[to] == true
end

-- Moves to `to` if allowed. Returns whether it moved; an illegal request changes nothing (so a duplicate final hit, a late
-- timer or a second reward attempt is simply refused).
function EncounterSM.to(enc: Encounter, to: string): boolean
	if not EncounterSM.can(enc, to) then
		return false
	end
	enc.state = to
	enc.transitions += 1
	if to == "REVEAL" then
		enc.spawns += 1
	elseif to == "SEALED" then
		enc.token += 1
	end
	return true
end

-- True while a creature exists in the world (it may be hurt only in COMBAT; REVEAL is its invulnerable emergence).
function EncounterSM.hasCreature(enc: Encounter): boolean
	return enc.state == "REVEAL" or enc.state == "COMBAT" or enc.state == "DEFEATED"
end

-- The player-facing label for the rock half, mapped from RockSim's stage names.
function EncounterSM.sealedLabel(rockStage: string): string
	if rockStage == "INTACT" then
		return "SEALED"
	elseif rockStage == "SURFACE" or rockStage == "CHIPPED" then
		return "DAMAGED"
	elseif rockStage == "FRACTURED" then
		return "FRACTURING"
	end
	return "SHATTERED"
end

return EncounterSM
