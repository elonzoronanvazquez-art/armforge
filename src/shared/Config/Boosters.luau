--!strict
-- Boosters: temporary additive bonuses to one stat. Stacking rules (documented in docs/GAME_RULES.md):
--  * Activating a booster you already have running EXTENDS its timer (up to maxDuration). It never doubles it.
--  * Different boosters of the same stat ADD their bonuses (never multiply), and the total is capped per stat.
--  * Timers only run while the player is in the game.

local Boosters = {}

export type BoosterDef = {
	id: string,
	name: string,
	blurb: string,
	stat: string,
	bonus: number,
	duration: number,
	maxDuration: number,
	color: Color3,
}

Boosters.Defs = {
	CoinSurge = {
		id = "CoinSurge",
		name = "Coin Surge",
		blurb = "+50% coins from rocks",
		stat = "coins",
		bonus = 0.5,
		duration = 600,
		maxDuration = 3600,
		color = Color3.fromRGB(255, 205, 70),
	},
	KnowledgeSurge = {
		id = "KnowledgeSurge",
		name = "Knowledge Surge",
		blurb = "+50% XP from rocks and training",
		stat = "xp",
		bonus = 0.5,
		duration = 600,
		maxDuration = 3600,
		color = Color3.fromRGB(120, 220, 140),
	},
	PowerSurge = {
		id = "PowerSurge",
		name = "Power Surge",
		blurb = "+25% arm damage",
		stat = "power",
		bonus = 0.25,
		duration = 300,
		maxDuration = 1800,
		color = Color3.fromRGB(255, 110, 80),
	},
	TrainingSurge = {
		id = "TrainingSurge",
		name = "Training Surge",
		blurb = "+50% training points",
		stat = "training",
		bonus = 0.5,
		duration = 600,
		maxDuration = 3600,
		color = Color3.fromRGB(110, 180, 255),
	},
	FocusSurge = {
		id = "FocusSurge",
		name = "Focus Surge",
		blurb = "+10% crit chance",
		stat = "crit",
		bonus = 0.10,
		duration = 300,
		maxDuration = 1800,
		color = Color3.fromRGB(200, 140, 255),
	},
} :: { [string]: BoosterDef }

Boosters.Order = { "CoinSurge", "KnowledgeSurge", "PowerSurge", "TrainingSurge", "FocusSurge" }

-- Total additive bonus allowed per stat from all boosters combined.
Boosters.StatCap = { coins = 1.5, xp = 1.5, power = 0.75, training = 1.5, crit = 0.25 } :: { [string]: number }

return Boosters
