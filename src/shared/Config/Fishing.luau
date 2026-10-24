--!strict
-- Dock fishing and the jungle's swing vines: timings, the catch table and the two teleport chances. Every number is data; the rules are in
-- Logic/Fishing and the glue in server/Services/FishingService and VineService.

local Fishing = {}

Fishing.Config = {
	biteMin = 2.5, -- seconds after casting before a fish bites
	biteMax = 6.5,
	reelWindow = 2.2, -- seconds you have to reel once it bites
	cooldown = 1.2, -- pause after a catch or a miss before the next cast
	idleCancel = 45, -- a cast nobody reels in is dropped after this long
	range = 18, -- studs from the fishing spot you must be within
	sailChance = 0.10, -- chance per CATCH that the tide pulls you out to The Atlantic Sea
	levelScale = 0.12, -- rewards grow by this fraction per player level above 1
}

export type Fish = { id: string, name: string, weight: number, coins: number, xp: number, text: string }

-- Weighted catch table. Coins / XP are base values (before the level scale, rebirth bonuses and boosters).
Fishing.Fish = {
	{ id = "Sardine", name = "Sardine", weight = 48, coins = 6, xp = 4, text = "A quick silver sardine." },
	{ id = "Mackerel", name = "Mackerel", weight = 30, coins = 12, xp = 8, text = "A stripy mackerel." },
	{ id = "Silverfin", name = "Silverfin", weight = 14, coins = 30, xp = 20, text = "A silverfin, flashing in the light." },
	{ id = "GoldenKoi", name = "Golden Koi", weight = 5, coins = 90, xp = 60, text = "A golden koi! Rare." },
	{ id = "OldBoot", name = "Old Boot", weight = 2.5, coins = 1, xp = 1, text = "An old boot. Better luck next time." },
	{ id = "SunkenCrown", name = "Sunken Crown", weight = 0.5, coins = 400, xp = 250, text = "A sunken crown! Very rare." },
} :: { Fish }

-- The jungle's swing vines: each swing has a small chance to fling you to The Canopy Grove.
Fishing.Vines = {
	teleportChance = 0.02,
	cooldown = 2.5, -- seconds per player between swings
	range = 14,
}

return Fishing
