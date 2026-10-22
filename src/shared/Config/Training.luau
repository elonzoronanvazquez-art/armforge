--!strict
-- Training stations. Each station trains one permanent stat; the mini-game for each runs on a server-owned clock
-- (see server/Services/TrainingService). Stat effects are per level and capped, so training helps without making rock
-- destruction pointless: the cap on trainable levels rises with player level.

local Training = {}

export type Station = {
	id: string,
	name: string,
	stat: string,
	blurb: string,
	unlockLevel: number,
	game: string, -- Timing | Tap | Targets | Rhythm
	color: Color3,
	icon: string,
}

Training.Stations = {
	Power = {
		id = "Power",
		name = "Power Press",
		stat = "power",
		blurb = "Time each press on the green band. Trains raw damage.",
		unlockLevel = 2,
		game = "Timing",
		color = Color3.fromRGB(255, 120, 70),
		icon = "P",
	},
	Haste = {
		id = "Haste",
		name = "Speed Bag",
		stat = "haste",
		blurb = "Tap as fast as you can for 10 seconds. Trains attack speed.",
		unlockLevel = 4,
		game = "Tap",
		color = Color3.fromRGB(255, 210, 80),
		icon = "H",
	},
	Precision = {
		id = "Precision",
		name = "Target Range",
		stat = "precision",
		blurb = "Strike each target as it flashes. Trains critical chance.",
		unlockLevel = 7,
		game = "Targets",
		color = Color3.fromRGB(110, 230, 255),
		icon = "X",
	},
	Endurance = {
		id = "Endurance",
		name = "Endurance Rig",
		stat = "endurance",
		blurb = "Hit every beat of the breathing rhythm. Trains skill cooldowns.",
		unlockLevel = 10,
		game = "Rhythm",
		color = Color3.fromRGB(150, 255, 150),
		icon = "E",
	},
} :: { [string]: Station }

Training.Order = { "Power", "Haste", "Precision", "Endurance" }

Training.Stats = {
	power = { name = "Power", perLevel = 0.015, maxLevel = 40, text = "+1.5% arm damage per level" },
	haste = { name = "Haste", perLevel = 0.008, maxLevel = 30, text = "+0.8% attack speed per level" },
	precision = { name = "Precision", perLevel = 0.004, maxLevel = 30, text = "+0.4% crit chance per level" },
	endurance = { name = "Endurance", perLevel = 0.01, maxLevel = 25, text = "-1% skill cooldown per level" },
} :: { [string]: { name: string, perLevel: number, maxLevel: number, text: string } }

Training.StatOrder = { "power", "haste", "precision", "endurance" }

-- Points needed to go from level L to L+1.
Training.PointsBase = 25
Training.PointsCoef = 12
Training.PointsExp = 1.3
-- A stat can only be trained up to LevelCapBase + LevelCapPerPlayerLevel * playerLevel (and its own max).
Training.LevelCapBase = 3
Training.LevelCapPerPlayerLevel = 1

-- Points awarded per rep by grade, and XP per point.
Training.GradePoints = { perfect = 10, great = 7, good = 4, miss = 0 }
Training.XpPerPoint = 0.5

-- Mini-game tuning
Training.Timing = { reps = 8, period = 1.5, zoneCenter = 0.78, perfect = 0.04, great = 0.09, good = 0.16, minGap = 0.55 }
Training.Tap = { duration = 10, maxRate = 9, minGap = 0.09, perfectRate = 6.5, greatRate = 5, goodRate = 3.2 }
Training.Targets = { reps = 8, visible = 1.3, gap = 0.45, radius = 0.09, perfect = 0.35, great = 0.6, good = 1.0, minReaction = 0.12 }
Training.Rhythm = { beats = 12, period = 0.85, lead = 1.2, perfect = 0.07, great = 0.14, good = 0.24 }

-- How far (studs) the player may be from a station to start or continue a session.
Training.StationRange = 16

return Training
