--!strict
-- Progression: XP curve, level rewards, rebirth rules. All numbers are centralised here (and tested in
-- tests/progression.spec.luau and tests/balance.spec.luau).

local Progression = {}

-- XP needed to go from level L to L+1:  floor(Base + Coef * L^Exp)
Progression.XpBase = 25
Progression.XpCoef = 15
Progression.XpExp = 1.95
Progression.MaxLevel = 40

Progression.SkillPointsPerLevel = 1
Progression.LevelUpCoins = 20 -- coins = LevelUpCoins * newLevel

-- Boosters / bonuses granted at specific levels.
Progression.LevelRewards = {
	[2] = { text = "Power Press unlocked", boosters = { CoinSurge = 1 } },
	[3] = { text = "Charged Smash can be learned. Stonebreaker Arms available.", skillNote = true },
	[4] = { text = "Speed Bag unlocked" },
	[5] = { text = "Critical Focus can be learned", boosters = { PowerSurge = 1 } },
	[7] = { text = "Overdrive can be learned. Target Range unlocked" },
	[8] = { text = "Alloy Arms available", boosters = { KnowledgeSurge = 1 } },
	[10] = { text = "Endurance Rig unlocked", boosters = { TrainingSurge = 1 } },
	[12] = { text = "Shatter Wave can be learned. Crystalfall Atoll unlocked!", boosters = { CoinSurge = 1, FocusSurge = 1 } },
	[14] = { text = "Crystal Arms available (Crystalfall)" },
	[20] = { text = "You are a true Forgemaster.", boosters = { PowerSurge = 2, KnowledgeSurge = 1 } },
	[25] = { text = "Emberfang Caldera needs one Rebirth", boosters = { CoinSurge = 2 } },
	[30] = { text = "You can REBIRTH now!", boosters = { TrainingSurge = 2, PowerSurge = 1 } },
} :: { [number]: { text: string, boosters: { [string]: number }?, skillNote: boolean? } }

-- Rebirth ---------------------------------------------------------------------------------------------
Progression.Rebirth = {
	minLevel = 30,
	baseCoinCost = 250000,
	costGrowth = 3,
	maxRebirths = 25,
	-- Permanent additive bonus per rebirth.
	bonusPerRebirth = { coins = 0.25, xp = 0.2, power = 0.1, training = 0.15 },
	-- Booster granted for each rebirth.
	reward = { boosters = { CoinSurge = 1, KnowledgeSurge = 1 }, shards = 0 },
	-- Data-driven reset rules. Anything not listed here is preserved.
	resets = {
		coins = true,
		level = true,
		xp = true,
		skillPoints = true,
		skillRanks = true,
		armUpgradeLevels = true,
		trainingStats = true,
	},
	preserves = {
		"arm ownership and the equipped arm",
		"cosmetics",
		"Forge Shards",
		"unlocked islands, guardian victories and island completion",
		"boosters (owned and running)",
		"rebirth count and permanent bonuses",
		"settings and tutorial progress",
	},
}

-- First-session guidance. Each step completes when the server records the matching flag in data.tutorial.
Progression.Tutorial = {
	{ id = "punch", text = "Walk up to a rock and PUNCH it! (Click, tap, or press the PUNCH button)", flag = "punched" },
	{ id = "destroy", text = "Keep hitting! Every rock has a creature imprisoned inside. Break it open, then FIGHT what comes out!", flag = "destroyed" },
	{ id = "upgrade", text = "You have coins! Open ARMS (F) and upgrade your fists.", flag = "upgraded" },
	{ id = "level", text = "Level up to unlock training, skills and new arms. Try the Power Press at the Training Yard.", flag = "trained" },
	{ id = "done", text = "Collect arms, rebirth, and sail to new islands from the Skyport. Good luck, Forgemaster.", flag = "finished" },
}

return Progression
