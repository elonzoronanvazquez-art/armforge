--!strict
-- Islands: the progression ladder. Requirements are checked by Logic/Islands (server authoritative and mirrored
-- in the UI). To add an island: append a def here, list its rock fields, and add a builder entry in the server's
-- World/WorldBuilder (see docs/ADDING_CONTENT.md).

local Islands = {}

export type Field = { name: string, center: Vector3, radius: number, rocks: { { rock: string, count: number } } }

-- An island's ultimate guardian: a sealed boss that can only be fought by players who have reached `rebirths`. Defeating it
-- (server-recorded, per player) completes the island. The NEXT island needs this victory AND this many rebirths.
export type GuardianDef = {
	creature: string, -- Config/Creatures id
	seal: string, -- Config/Rocks seal id that releases it
	position: Vector3, -- where the seal stands (snapped to the terrain)
	rebirths: number,
}

-- An optional extra boss on an island: sealed in its own seal rock, fought like a guardian (rebirth gate, phases) but it gates nothing and
-- can be fought again after its seal re-forms.
export type MiniBossDef = {
	creature: string,
	seal: string,
	position: Vector3,
	rebirths: number,
}

-- A timed boost an island grants for a feat (Config/Mountain: finishing a climb route or riding the tramway up). Logic/Momentum.
export type Momentum = { coins: number, xp: number, seconds: number }

-- Per-biome reward multipliers: everything earned on the island (rock mining and creature fights) is multiplied by these.
export type Boost = { coins: number, xp: number }

export type IslandDef = {
	id: string,
	name: string,
	biome: string, -- starter | jungle | mountain | volcano | steampunk | desert | void
	tagline: string,
	description: string,
	order: number,
	requires: { level: number?, rebirths: number?, coins: number? },
	boost: Boost?, -- nil = no boost
	momentum: Momentum?, -- timed boost for climbing / riding (Frostpeak)
	miniBosses: { MiniBossDef }?,
	guardian: GuardianDef?, -- nil while the island is not playable yet
	comingSoon: boolean?,
	center: Vector3,
	radius: number,
	arrival: Vector3, -- world position the player is placed at
	fields: { Field },
	accent: Color3,
	sky: Color3,
	fog: Color3,
	ambient: Color3,
}

Islands.Defs = {
	Forgeheart = {
		id = "Forgeheart",
		name = "Forgeheart Isle",
		biome = "starter",
		tagline = "Where every arm begins",
		description = "The old arm-forging works. Granite, ironvein and rare prism geodes surround the Great Forge. A fishing dock juts into the bay.",
		order = 1,
		requires = {},
		center = Vector3.new(0, 0, 0),
		radius = 270,
		arrival = Vector3.new(0, 4, 78),
		fields = {
			{
				name = "Starter Field",
				center = Vector3.new(-6, 0, -118),
				radius = 52,
				rocks = { { rock = "Granite", count = 8 }, { rock = "Ironvein", count = 3 } },
			},
			{
				name = "Deep Quarry",
				center = Vector3.new(128, 0, -138),
				radius = 46,
				rocks = { { rock = "Ironvein", count = 5 }, { rock = "Granite", count = 3 }, { rock = "Prism", count = 2 }, { rock = "Forgestone", count = 2 } },
			},
		},
		guardian = { creature = "GromAnvilKing", seal = "AnvilSeal", position = Vector3.new(-150, 0, -70), rebirths = 1 },
		accent = Color3.fromRGB(255, 150, 60),
		sky = Color3.fromRGB(255, 188, 120),
		fog = Color3.fromRGB(255, 196, 150),
		ambient = Color3.fromRGB(120, 112, 124),
	},
	Mossveil = {
		id = "Mossveil",
		name = "Mossveil Jungle",
		biome = "jungle",
		tagline = "Where the old forge went green",
		description = "A drowned-green jungle: a great lake, a roaring waterfall, mossy stone and vines older than the forge.",
		order = 2,
		requires = { level = 5 },
		center = Vector3.new(0, 0, 820),
		radius = 200,
		arrival = Vector3.new(0, 4, 916),
		fields = {
			{
				name = "Fern Hollow",
				center = Vector3.new(-70, 0, 770),
				radius = 50,
				rocks = { { rock = "MossStone", count = 8 }, { rock = "Rootstone", count = 3 } },
			},
			{
				name = "Jade Terrace",
				center = Vector3.new(20, 0, 676),
				radius = 42,
				rocks = { { rock = "Rootstone", count = 5 }, { rock = "MossStone", count = 3 }, { rock = "Jadeheart", count = 2 } },
			},
		},
		guardian = { creature = "YmiraRootmother", seal = "RootSeal", position = Vector3.new(-135, 0, 850), rebirths = 2 },
		accent = Color3.fromRGB(120, 220, 110),
		sky = Color3.fromRGB(150, 210, 150),
		fog = Color3.fromRGB(150, 205, 160),
		ambient = Color3.fromRGB(86, 120, 92),
	},
	Crystalfall = {
		id = "Crystalfall",
		name = "Frostpeak Mountain",
		biome = "mountain",
		tagline = "The mountain that sings",
		description = "A huge snowbound mountain. Snow-capped rocks and three mini bosses ring Base Camp; climb the crown or ride the tram to the summit, where the Choir waits. Summit feats grant +50% XP and +7% coins for a while.",
		order = 3,
		requires = { level = 12 },
		center = Vector3.new(820, 0, 0),
		radius = 190,
		arrival = Vector3.new(820, 4, 96),
		fields = {
			{
				name = "Snowdrift Meadow",
				center = Vector3.new(730, 0, 68),
				radius = 48,
				rocks = { { rock = "Quartz", count = 8 }, { rock = "Amethyst", count = 3 } },
			},
			{
				name = "Crystal Ledge",
				center = Vector3.new(871, 0, -68),
				radius = 20,
				rocks = { { rock = "Amethyst", count = 3 }, { rock = "Quartz", count = 3 }, { rock = "Heartstone", count = 2 } },
			},
		},
		guardian = { creature = "LyraeFrozenChorus", seal = "ChoirSeal", position = Vector3.new(820, 0, -50), rebirths = 3 },
		momentum = { coins = 1.07, xp = 1.5, seconds = 300 },
		miniBosses = {
			{ creature = "HoarfangYeti", seal = "HoarSeal", position = Vector3.new(872, 0, -31), rebirths = 2 },
			{ creature = "GlaciermawWyrm", seal = "RimeSeal", position = Vector3.new(768, 0, -31), rebirths = 2 },
			{ creature = "AvalancheTitan", seal = "AvalancheSeal", position = Vector3.new(801, 0, -102), rebirths = 2 },
		},
		accent = Color3.fromRGB(110, 220, 255),
		sky = Color3.fromRGB(170, 190, 255),
		fog = Color3.fromRGB(190, 200, 255),
		ambient = Color3.fromRGB(110, 120, 170),
	},
	Emberfang = {
		id = "Emberfang",
		name = "Emberfang Volcano",
		biome = "volcano",
		tagline = "The furnace beneath the world",
		description = "A smoking volcano of black basalt and living magma: lava rivers, molten rocks, scorched trees and a crater where the Sovereign sleeps. It pays 50% more of everything.",
		order = 4,
		requires = { level = 25 },
		boost = { coins = 1.5, xp = 1.5 },
		center = Vector3.new(-820, 0, 0),
		radius = 190,
		arrival = Vector3.new(-820, 4, 96),
		fields = {
			{
				name = "Basalt Flats",
				center = Vector3.new(-920, 0, 10),
				radius = 54,
				rocks = { { rock = "Basalt", count = 8 }, { rock = "MagmaCore", count = 3 } },
			},
			{
				name = "Cinder Terrace",
				center = Vector3.new(-732, 0, -35),
				radius = 30,
				rocks = { { rock = "MagmaCore", count = 5 }, { rock = "Basalt", count = 3 }, { rock = "Obsidian", count = 2 } },
			},
		},
		guardian = { creature = "CinderjawSovereign", seal = "CalderaSeal", position = Vector3.new(-828, 0, -35), rebirths = 4 },
		accent = Color3.fromRGB(255, 96, 40),
		sky = Color3.fromRGB(110, 54, 52),
		fog = Color3.fromRGB(120, 60, 50),
		ambient = Color3.fromRGB(130, 80, 74),
	},
	Cogspire = {
		id = "Cogspire",
		name = "Cogspire Foundry",
		biome = "steampunk",
		tagline = "Brass, steam and ten thousand gears",
		description = "A steampunk foundry city: brass towers, pressure pipes, spinning gears and a Great Clock whose engine will not stay asleep.",
		order = 5,
		requires = { level = 28 },
		center = Vector3.new(820, 0, 820),
		radius = 200,
		arrival = Vector3.new(820, 4, 916),
		fields = {
			{
				name = "Boiler Yard",
				center = Vector3.new(740, 0, 830),
				radius = 52,
				rocks = { { rock = "Cogstone", count = 8 }, { rock = "Boilerplate", count = 3 } },
			},
			{
				name = "Aether Works",
				center = Vector3.new(900, 0, 800),
				radius = 38,
				rocks = { { rock = "Boilerplate", count = 5 }, { rock = "Cogstone", count = 3 }, { rock = "Aetherglass", count = 2 } },
			},
		},
		guardian = { creature = "CogheartEngine", seal = "ValveSeal", position = Vector3.new(820, 0, 812), rebirths = 5 },
		accent = Color3.fromRGB(214, 150, 70),
		sky = Color3.fromRGB(214, 176, 120),
		fog = Color3.fromRGB(190, 160, 120),
		ambient = Color3.fromRGB(130, 108, 84),
	},
	Dustwake = {
		id = "Dustwake",
		name = "Dustwake Ruins",
		biome = "desert",
		tagline = "The forgotten sands",
		description = "A forgotten desert. Ancient temples lie half-exposed and half-buried under the dunes, and something still sleeps below.",
		order = 6,
		requires = { level = 30 },
		center = Vector3.new(-820, 0, 820),
		radius = 200,
		arrival = Vector3.new(-820, 4, 916),
		fields = {
			{
				name = "Dune Quarry",
				center = Vector3.new(-880, 0, 770),
				radius = 54,
				rocks = { { rock = "Sandblock", count = 8 }, { rock = "Relic", count = 3 } },
			},
			{
				name = "Ruin Court",
				center = Vector3.new(-780, 0, 690),
				radius = 44,
				rocks = { { rock = "Relic", count = 5 }, { rock = "Sandblock", count = 3 }, { rock = "Sunstone", count = 2 } },
			},
		},
		guardian = { creature = "OszarakBuriedSovereign", seal = "SunkenSeal", position = Vector3.new(-905, 0, 865), rebirths = 6 },
		accent = Color3.fromRGB(240, 190, 90),
		sky = Color3.fromRGB(240, 200, 140),
		fog = Color3.fromRGB(235, 200, 150),
		ambient = Color3.fromRGB(150, 124, 96),
	},
	Voidreach = {
		id = "Voidreach",
		name = "Voidreach",
		biome = "void",
		tagline = "Beyond the last forge",
		description = "Something is humming out past the edge of the map. Not yet charted.",
		order = 7,
		requires = { level = 34 },
		comingSoon = true,
		center = Vector3.new(0, 0, -1000),
		radius = 190,
		arrival = Vector3.new(0, 4, -900),
		fields = {},
		accent = Color3.fromRGB(190, 120, 255),
		sky = Color3.fromRGB(26, 18, 48),
		fog = Color3.fromRGB(40, 28, 70),
		ambient = Color3.fromRGB(90, 70, 130),
	},
} :: { [string]: IslandDef }

-- The ladder: Starter Island -> Jungle -> Mountain -> Volcano -> Steampunk -> Desert -> teaser. Islands without a guardian
-- (still coming soon) are skipped by the guardian gate, so the next playable island opens from the last guarded one
-- (Logic/Islands.previousGuarded / nextPlayable).
Islands.Order = { "Forgeheart", "Mossveil", "Crystalfall", "Emberfang", "Cogspire", "Dustwake", "Voidreach" }
Islands.Start = "Forgeheart"

-- Crystalfall is now the Mountain (guardian seal on the summit) and Emberfang the Volcano (seal on the crater floor); both keep their
-- internal ids. Cogspire is the steampunk foundry; Voidreach is still a teaser without a guardian.

return Islands
