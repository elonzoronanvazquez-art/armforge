--!strict
-- What a player can learn about a sealed rock before breaking it: the creature inside, how dangerous it is and what to bring.
-- RockService publishes this as attributes on the rock model; the client shows it on the targeted rock. Pure, so it is tested.

local Config = script.Parent.Parent.Config
local Creatures = require(Config.Creatures)
local Islands = require(Config.Islands)

local EncounterInfo = {}

export type Info = {
	Contains: string,
	ContainsTitle: string,
	Tier: string,
	Size: string,
	Danger: number, -- 1..5
	Recommended: string,
	RecommendedLevel: number,
	GuardianRebirths: number, -- boss seals only: the rebirths needed to break the seal
	Skills: string, -- comma separated skill ids that matter
}

-- Skulls: normal creatures 1-2 (armored ones are the harder 2), elites 4, guardians 5.
function EncounterInfo.danger(c: Creatures.CreatureDef): number
	if c.tier == "boss" then
		return 5
	elseif c.tier == "elite" then
		return 4
	end
	return if c.armor then 2 else 1
end

function EncounterInfo.forCreature(c: Creatures.CreatureDef, size: string, island: string): Info
	local gate = 0
	if c.tier == "boss" then
		local g = Islands.Defs[island].guardian
		gate = if g then g.rebirths else 0
	end
	return {
		Contains = c.name,
		ContainsTitle = c.title,
		Tier = c.tier,
		Size = size,
		Danger = EncounterInfo.danger(c),
		Recommended = c.recommended.text,
		RecommendedLevel = c.recommended.level,
		GuardianRebirths = gate,
		Skills = table.concat(c.recommended.skills, ","),
	}
end

return EncounterInfo
