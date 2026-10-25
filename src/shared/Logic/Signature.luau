--!strict
-- Signature move rules shared by server and client: who has one, when it is ready, how long its cooldown is, and how much
-- damage it is worth (so tests can keep it in line with the skills).

local Config = script.Parent.Parent.Config
local SignatureConfig = require(Config.Signatures)
local Formulas = require(script.Parent.Formulas)

local Signature = {}

export type Def = SignatureConfig.SignatureDef

function Signature.def(armId: string): Def?
	return SignatureConfig.Defs[armId]
end

-- The cooldown id kept in Combat.State.skillReady (and sent to the client with the skill cooldowns).
function Signature.key(armId: string): string
	return "Sig:" .. armId
end

-- Cooldown in seconds after Endurance training (the same reduction the skills get).
function Signature.cooldown(data: any, armId: string): number
	local def = SignatureConfig.Defs[armId]
	if not def then
		return math.huge
	end
	local reduction = math.min(0.5, Formulas.trainingStatBonus({ endurance = data.training.endurance.level }, "endurance"))
	return def.cooldown * (1 - reduction)
end

-- Seconds until it can be used again (0 when ready).
function Signature.remaining(state: { skillReady: { [string]: number } }, armId: string, now: number): number
	return math.max(0, (state.skillReady[Signature.key(armId)] or 0) - now)
end

-- Total multiplier of power the move delivers to a single target (strikes plus the burst's share if it hits one more).
function Signature.worth(def: Def): number
	local total = 0
	for _, s in def.strikes do
		total += s.mult
	end
	if def.burst then
		total += def.burst.mult
	end
	return total
end

return Signature
