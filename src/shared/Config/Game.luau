--!strict
-- Global constants: budgets, combat tuning, networking limits, persistence. Balance numbers live in the other
-- Config modules; this file is about "how the game runs".

local Game = {}

Game.Name = "ARMFORGE"
Game.Version = "0.1.0"

-- Persistence --------------------------------------------------------------------------------------------
Game.Data = {
	storeName = "ARMFORGE_PlayerData",
	storeScope = "v1",
	schemaVersion = 1,
	autosaveInterval = 75, -- seconds
	saveRetries = 4,
	sessionLockTimeout = 600, -- seconds before a stale session lock may be stolen
	loadRetries = 5,
}

-- Networking ---------------------------------------------------------------------------------------------
-- Token bucket per player per remote: rate tokens/second, burst capacity.
Game.RateLimits = {
	Punch = { rate = 9, burst = 6 },
	Skill = { rate = 3, burst = 4 },
	Request = { rate = 6, burst = 10 },
	Training = { rate = 18, burst = 20 },
	Setting = { rate = 4, burst = 6 },
}

-- Combat -------------------------------------------------------------------------------------------------
Game.Combat = {
	-- Server accepts a strike if the character is within arm reach + rock radius + this slack (latency).
	reachSlack = 6,
	-- A strike may arrive this much earlier than the cooldown allows (network jitter).
	cooldownTolerance = 0.09,
	-- Anything faster than this fraction of base cooldown is clamped (haste can never exceed it).
	minCooldown = 0.18,
	fxRadius = 120, -- clients within this many studs receive hit effects
	comboWindow = 1.3, -- seconds between strikes that keeps a combo alive
	maxHasteBonus = 1.0, -- total attack speed bonus cap (+100%)
	maxCritChance = 0.85,
	autoTargetAngle = 0.25, -- dot product threshold for the facing cone (client assist)
	-- Cooperative payout: contributors with >= this share of the rock's HP get the full reward.
	fullPayoutShare = 0.1,
	lastHitBonus = 0.1,
}

-- Rocks --------------------------------------------------------------------------------------------------
Game.Rocks = {
	aftermath = 1.6, -- seconds the rubble stays before respawn timer starts
	maxActive = 160, -- hard cap on live rocks per server
	minSpacing = 11,
	groundOffset = 0,
	healOnIdle = false,
}

-- Budgets (client effects) -------------------------------------------------------------------------------
Game.Budgets = {
	debrisMax = 56, -- simultaneous client debris parts
	debrisPerHit = 5,
	debrisPerBreak = 20,
	sparksPerHit = 14,
	soundsMax = 10,
	damageNumbersMax = 8,
	shakeMax = 1.0,
	impactLightsMax = 3,
}

-- Studio-only development tools (ignored in live servers, see server/Dev) ------------------------------------
Game.Dev = {
	enabledInStudioOnly = true,
	progressionMultiplier = 1, -- multiplies coins and XP in Studio when > 1
}

-- Starting resources -----------------------------------------------------------------------------------
Game.Start = { coins = 0, shards = 0, level = 1, island = "Forgeheart" }

return Game
