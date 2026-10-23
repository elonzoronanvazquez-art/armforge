--!strict
-- Islands: the progression ladder. Requirements are checked by Logic/Islands (server authoritative and mirrored
-- in the UI). To add an island: append a def here, list its rock fields, and add a builder entry in the server's
-- World/IslandBuilders (see docs/ADDING_CONTENT.md).

local Islands = {}

export type Field = { name: string, center: Vector3, radius: number, rocks: { { rock: string, count: number } } }

export type IslandDef = {
	id: string,
	name: string,
	tagline: string,
	description: string,
	order: number,
	requires: { level: number?, rebirths: number?, coins: number? },
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
		tagline = "Where every arm begins",
		description = "The old arm-forging works. Granite, ironvein and rare prism geodes surround the Great Forge.",
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
				rocks = { { rock = "Granite", count = 10 }, { rock = "Ironvein", count = 2 } },
			},
			{
				name = "Deep Quarry",
				center = Vector3.new(128, 0, -138),
				radius = 46,
				rocks = { { rock = "Ironvein", count = 6 }, { rock = "Granite", count = 4 }, { rock = "Prism", count = 2 } },
			},
		},
		accent = Color3.fromRGB(255, 150, 60),
		sky = Color3.fromRGB(255, 188, 120),
		fog = Color3.fromRGB(255, 196, 150),
		ambient = Color3.fromRGB(120, 112, 124),
	},
	Crystalfall = {
		id = "Crystalfall",
		name = "Crystalfall Atoll",
		tagline = "The island that sings",
		description = "Frozen waterfalls of crystal. Quartz spires, amethyst clusters and golden Heartstone geodes.",
		order = 2,
		requires = { level = 12 },
		center = Vector3.new(820, 0, 0),
		radius = 190,
		arrival = Vector3.new(820, 4, 96),
		fields = {
			{
				name = "Quartz Meadow",
				center = Vector3.new(820, 0, -50),
				radius = 58,
				rocks = { { rock = "Quartz", count = 10 }, { rock = "Amethyst", count = 3 } },
			},
			{
				name = "Geode Basin",
				center = Vector3.new(904, 0, -96),
				radius = 44,
				rocks = { { rock = "Amethyst", count = 6 }, { rock = "Quartz", count = 3 }, { rock = "Heartstone", count = 2 } },
			},
		},
		accent = Color3.fromRGB(110, 220, 255),
		sky = Color3.fromRGB(170, 190, 255),
		fog = Color3.fromRGB(190, 200, 255),
		ambient = Color3.fromRGB(110, 120, 170),
	},
	Emberfang = {
		id = "Emberfang",
		name = "Emberfang Caldera",
		tagline = "The furnace beneath the world",
		description = "A volcanic caldera of black basalt and living magma. Only reforged arms survive the heat.",
		order = 3,
		requires = { level = 25, rebirths = 1 },
		center = Vector3.new(-820, 0, 0),
		radius = 190,
		arrival = Vector3.new(-820, 4, 96),
		fields = {
			{
				name = "Basalt Flats",
				center = Vector3.new(-820, 0, -50),
				radius = 58,
				rocks = { { rock = "Basalt", count = 10 }, { rock = "MagmaCore", count = 3 } },
			},
			{
				name = "Caldera Rim",
				center = Vector3.new(-904, 0, -96),
				radius = 44,
				rocks = { { rock = "MagmaCore", count = 6 }, { rock = "Basalt", count = 3 }, { rock = "Obsidian", count = 2 } },
			},
		},
		accent = Color3.fromRGB(255, 96, 40),
		sky = Color3.fromRGB(110, 54, 52),
		fog = Color3.fromRGB(120, 60, 50),
		ambient = Color3.fromRGB(130, 80, 74),
	},
	Voidreach = {
		id = "Voidreach",
		name = "Voidreach",
		tagline = "Beyond the last forge",
		description = "Something is humming out past the edge of the map. Not yet charted.",
		order = 4,
		requires = { level = 30, rebirths = 3 },
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

Islands.Order = { "Forgeheart", "Crystalfall", "Emberfang", "Voidreach" }
Islands.Start = "Forgeheart"

return Islands
