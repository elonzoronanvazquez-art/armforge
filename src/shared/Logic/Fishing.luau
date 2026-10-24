--!strict
-- Fishing rules, pure: a cast waits a random time for a bite, then the angler has a short window to reel; early or late reels catch nothing.
-- A catch is a weighted roll from Config/Fishing.Fish, scaled by player level, with a flat chance to be pulled out to The Atlantic Sea.
-- All randomness comes from the Rng passed in, so the server, the dev tools and the tests share one deterministic implementation.

local Config = script.Parent.Parent.Config
local FishingConfig = require(Config.Fishing)

local Fishing = {}

export type Cast = { castAt: number, biteAt: number, expiresAt: number }
export type Catch = { fish: FishingConfig.Fish, coins: number, xp: number, sail: boolean }

type RngLike = { next: (any) -> number, range: (any, number, number) -> number }

-- Starts a cast at `now`.
function Fishing.cast(now: number, rng: RngLike): Cast
	local cfg = FishingConfig.Config
	local biteAt = now + rng:range(cfg.biteMin, cfg.biteMax)
	return { castAt = now, biteAt = biteAt, expiresAt = biteAt + cfg.reelWindow }
end

-- What reeling at `now` does: "early" (nothing there yet), "caught" (inside the window), "missed" (it got away).
function Fishing.reel(cast: Cast, now: number): string
	if now < cast.biteAt then
		return "early"
	elseif now <= cast.expiresAt then
		return "caught"
	end
	return "missed"
end

function Fishing.levelScale(level: number): number
	return 1 + math.max(0, level - 1) * FishingConfig.Config.levelScale
end

-- Rolls a catch for a player of `level`.
function Fishing.roll(rng: RngLike, level: number): Catch
	local total = 0
	for _, fish in FishingConfig.Fish do
		total += fish.weight
	end
	local pick = rng:next() * total
	local chosen = FishingConfig.Fish[#FishingConfig.Fish]
	for _, fish in FishingConfig.Fish do
		pick -= fish.weight
		if pick <= 0 then
			chosen = fish
			break
		end
	end
	local scale = Fishing.levelScale(level)
	return {
		fish = chosen,
		coins = math.max(1, math.floor(chosen.coins * scale)),
		xp = math.max(1, math.floor(chosen.xp * scale)),
		sail = rng:next() < FishingConfig.Config.sailChance,
	}
end

-- A swing on a jungle vine: does it fling the player to the Canopy Grove?
function Fishing.vineFlings(rng: RngLike): boolean
	return rng:next() < FishingConfig.Vines.teleportChance
end

return Fishing
