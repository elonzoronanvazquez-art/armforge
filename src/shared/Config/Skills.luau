--!strict
-- Active arm skills. Learned with skill points (1 per level) once the player reaches `unlockLevel`.
-- Numeric effects per rank live in Logic/Skills so the tradeoffs sit next to the code that applies them.

local Skills = {}

export type SkillDef = {
	id: string,
	name: string,
	blurb: string,
	tradeoff: string,
	unlockLevel: number,
	maxRank: number,
	cooldown: number,
	key: number,
	rankCost: { number },
	color: Color3,
}

Skills.Defs = {
	ChargedSmash = {
		id = "ChargedSmash",
		name = "Charged Smash",
		blurb = "Rear back and bring both arms down on the target for a huge hit.",
		tradeoff = "Slow wind-up; long cooldown.",
		unlockLevel = 3,
		maxRank = 5,
		cooldown = 7,
		key = 1,
		rankCost = { 1, 2, 3, 4, 5 },
		color = Color3.fromRGB(255, 170, 70),
	},
	CriticalFocus = {
		id = "CriticalFocus",
		name = "Critical Focus",
		blurb = "Lock in. Your next strikes crit far more often.",
		tradeoff = "Short window; no extra raw damage.",
		unlockLevel = 5,
		maxRank = 5,
		cooldown = 22,
		key = 2,
		rankCost = { 1, 2, 3, 4, 5 },
		color = Color3.fromRGB(120, 230, 255),
	},
	Overdrive = {
		id = "Overdrive",
		name = "Overdrive",
		blurb = "Redline the arms: strike much faster for a few seconds.",
		tradeoff = "Overheat: attack speed drops for a few seconds afterwards.",
		unlockLevel = 7,
		maxRank = 5,
		cooldown = 28,
		key = 3,
		rankCost = { 1, 2, 3, 4, 5 },
		color = Color3.fromRGB(255, 96, 70),
	},
	ShatterWave = {
		id = "ShatterWave",
		name = "Shatter Wave",
		blurb = "Slam the ground. A shockwave batters up to four rocks around you.",
		tradeoff = "Splits damage across targets; weaker than a direct hit.",
		unlockLevel = 12,
		maxRank = 5,
		cooldown = 16,
		key = 4,
		rankCost = { 2, 3, 4, 5, 6 },
		color = Color3.fromRGB(190, 130, 255),
	},
} :: { [string]: SkillDef }

Skills.Order = { "ChargedSmash", "CriticalFocus", "Overdrive", "ShatterWave" }

-- Per-rank effect tables (index = rank). Applied by Logic/Skills.
Skills.Effects = {
	ChargedSmash = { damageMult = { 3.0, 3.5, 4.0, 4.6, 5.3 }, windup = 0.55, minChunks = 3 },
	CriticalFocus = { critBonus = { 0.25, 0.30, 0.35, 0.40, 0.45 }, duration = { 6, 6.5, 7, 7.5, 8 } },
	Overdrive = {
		hasteBonus = { 0.35, 0.40, 0.45, 0.50, 0.55 },
		powerBonus = { 0.10, 0.12, 0.14, 0.16, 0.18 },
		duration = { 7, 7.5, 8, 8.5, 9 },
		overheat = { duration = 4, hastePenalty = 0.2 },
	},
	ShatterWave = { damageMult = { 0.9, 1.0, 1.1, 1.2, 1.35 }, radius = { 15, 16, 17, 18, 20 }, maxTargets = 4 },
}

return Skills
