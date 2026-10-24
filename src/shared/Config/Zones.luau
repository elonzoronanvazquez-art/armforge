--!strict
-- Zones: places that are NOT rungs of the island ladder. You reach them by an event, not by the Skyport, so they have no unlock rules and
-- are never listed in the Islands panel:
--   The Atlantic Sea  a fishing trip can pull you out to it (Config/Fishing); +25% coins and XP on everything earned there
--   The Canopy Grove  a rare vine swing in the Mossveil jungle can fling you up to it (Config/Fishing.Vines); a secret gift waits there
-- A player is "in" a zone while session.zone names it; dying or sailing home clears it (Services/ZoneService).

local Islands = require(script.Parent.Islands)

local Zones = {}

export type ZoneDef = {
	id: string,
	name: string,
	tagline: string,
	description: string,
	center: Vector3,
	radius: number,
	arrival: Vector3, -- where a visitor lands
	boost: Islands.Boost?, -- coins and XP multipliers for everything earned here
	fields: { Islands.Field },
	floating: boolean?, -- a platform in the sky: no terrain is generated
	home: string?, -- island id visitors are sent back to (default: the island they were last on)
	gift: { rock: string, mult: number, cooldown: number }?, -- a repeatable gift worth `mult` x the reference rock's coins and XP
	accent: Color3,
	sky: Color3,
	fog: Color3,
	ambient: Color3,
}

Zones.Defs = {
	AtlanticSea = {
		id = "AtlanticSea",
		name = "The Atlantic Sea",
		tagline = "The tide pulled you out",
		description = "A reef atoll far out in open water. Everything you earn here pays 25% more coins and XP.",
		center = Vector3.new(-450, 0, -520),
		radius = 130,
		arrival = Vector3.new(-450, 4, -446),
		boost = { coins = 1.25, xp = 1.25 },
		fields = {
			{
				name = "Reef Shallows",
				center = Vector3.new(-486, 0, -548),
				radius = 32,
				rocks = { { rock = "Brinerock", count = 6 }, { rock = "Coralstone", count = 3 } },
			},
			{
				name = "Pearl Bank",
				center = Vector3.new(-410, 0, -566),
				radius = 28,
				rocks = { { rock = "Coralstone", count = 3 }, { rock = "Brinerock", count = 2 }, { rock = "Pearlheart", count = 2 } },
			},
		},
		accent = Color3.fromRGB(80, 220, 230),
		sky = Color3.fromRGB(150, 220, 240),
		fog = Color3.fromRGB(160, 225, 240),
		ambient = Color3.fromRGB(110, 150, 160),
	},
	CanopyGrove = {
		id = "CanopyGrove",
		name = "The Canopy Grove",
		tagline = "A secret above the jungle",
		description = "A hidden platform of jade and blossoms high over Mossveil. The Rootmother leaves a gift here.",
		center = Vector3.new(-60, 150, 700),
		radius = 34,
		arrival = Vector3.new(-60, 154, 700),
		fields = {},
		floating = true,
		home = "Mossveil",
		gift = { rock = "Rootstone", mult = 8, cooldown = 300 },
		accent = Color3.fromRGB(150, 255, 160),
		sky = Color3.fromRGB(170, 230, 170),
		fog = Color3.fromRGB(160, 220, 170),
		ambient = Color3.fromRGB(100, 140, 100),
	},
} :: { [string]: ZoneDef }

Zones.Order = { "AtlanticSea", "CanopyGrove" }

return Zones
