--!strict
-- Summit Momentum: a timed reward boost an island grants for a feat (on Frostpeak: finishing a climb route or riding the tramway up).
-- It is transient session state, never saved, and it only boosts what is earned ON the island that granted it. Pure and tested.

local IslandConfig = require(script.Parent.Parent.Config.Islands)

local Momentum = {}

export type State = { island: string, untilT: number }
export type Holder = { momentum: State? }

-- Starts (or refreshes) the island's momentum for the holder. False when the island has none.
function Momentum.grant(holder: Holder, islandId: string, now: number): boolean
	local def = IslandConfig.Defs[islandId]
	local cfg = def and def.momentum
	if not cfg then
		return false
	end
	holder.momentum = { island = islandId, untilT = now + cfg.seconds }
	return true
end

function Momentum.remaining(holder: Holder, now: number): number
	local m = holder.momentum
	if not m then
		return 0
	end
	return math.max(0, m.untilT - now)
end

-- The multipliers for a reward earned on `islandId`: the active momentum if it is for that island, otherwise 1 / 1.
function Momentum.multipliers(holder: Holder, islandId: string, now: number): { coins: number, xp: number }
	local m = holder.momentum
	if m and m.island == islandId and m.untilT > now then
		local cfg = IslandConfig.Defs[islandId].momentum
		if cfg then
			return { coins = cfg.coins, xp = cfg.xp }
		end
	end
	return { coins = 1, xp = 1 }
end

-- "+50% XP, +7% coins" for UI.
function Momentum.text(islandId: string): string?
	local def = IslandConfig.Defs[islandId]
	local cfg = def and def.momentum
	if not cfg then
		return nil
	end
	return `+{math.floor((cfg.xp - 1) * 100 + 0.5)}% XP, +{math.floor((cfg.coins - 1) * 100 + 0.5)}% coins`
end

return Momentum
