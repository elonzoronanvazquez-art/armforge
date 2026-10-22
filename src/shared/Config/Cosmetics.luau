--!strict
-- Cosmetics are owned and equipped per arm and never touch stats.
-- Ownership keys are "<kind>:<id>" in PlayerData.cosmetics.owned (e.g. "palette:Ember").

local Cosmetics = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

export type Palette = { name: string, cost: number, primary: Color3?, secondary: Color3?, glow: Color3? }
export type Finish = { name: string, cost: number, reflectance: number, material: Enum.Material? }
export type Trail = { name: string, cost: number, color: Color3? }
export type Glow = { name: string, cost: number, scale: number }

-- Palettes override the arm's primary / secondary / glow colours.
Cosmetics.Palettes = {
	Default = { name = "Signature", cost = 0 },
	Ember = { name = "Emberforged", cost = 600, primary = rgb(90, 52, 44), secondary = rgb(255, 120, 40), glow = rgb(255, 170, 60) },
	Glacier = { name = "Glacier", cost = 600, primary = rgb(184, 214, 236), secondary = rgb(70, 120, 190), glow = rgb(140, 230, 255) },
	Verdant = { name = "Verdant", cost = 900, primary = rgb(70, 110, 78), secondary = rgb(190, 214, 90), glow = rgb(150, 255, 130) },
	Royal = { name = "Royal Violet", cost = 1500, primary = rgb(52, 36, 96), secondary = rgb(255, 205, 80), glow = rgb(210, 150, 255) },
	Bone = { name = "Bonewhite", cost = 1200, primary = rgb(236, 230, 214), secondary = rgb(120, 100, 84), glow = rgb(255, 232, 170) },
} :: { [string]: Palette }
Cosmetics.PaletteOrder = { "Default", "Ember", "Glacier", "Verdant", "Royal", "Bone" }

Cosmetics.Finishes = {
	Standard = { name = "Standard", cost = 0, reflectance = 0 },
	Polished = { name = "Polished", cost = 800, reflectance = 0.28, material = Enum.Material.Metal },
	Matte = { name = "Matte", cost = 500, reflectance = 0, material = Enum.Material.Slate },
	Weathered = { name = "Weathered", cost = 500, reflectance = 0, material = Enum.Material.CorrodedMetal },
} :: { [string]: Finish }
Cosmetics.FinishOrder = { "Standard", "Polished", "Matte", "Weathered" }

-- Trails also tint the impact sparks of that arm.
Cosmetics.Trails = {
	Default = { name = "Arm Glow", cost = 0 },
	Ember = { name = "Ember", cost = 700, color = rgb(255, 140, 50) },
	Frost = { name = "Frostline", cost = 700, color = rgb(120, 225, 255) },
	Toxic = { name = "Toxic", cost = 1000, color = rgb(150, 255, 90) },
	Royal = { name = "Royal", cost = 1600, color = rgb(205, 130, 255) },
	Mono = { name = "Chalk", cost = 400, color = rgb(245, 245, 250) },
} :: { [string]: Trail }
Cosmetics.TrailOrder = { "Default", "Ember", "Frost", "Toxic", "Royal", "Mono" }

Cosmetics.Glows = {
	Dim = { name = "Dim", cost = 0, scale = 0.55 },
	Normal = { name = "Normal", cost = 0, scale = 1 },
	Bright = { name = "Bright", cost = 400, scale = 1.6 },
} :: { [string]: Glow }
Cosmetics.GlowOrder = { "Dim", "Normal", "Bright" }

Cosmetics.Defaults = { palette = "Default", finish = "Standard", trail = "Default", glow = "Normal" }

Cosmetics.Kinds = {
	palette = Cosmetics.Palettes,
	finish = Cosmetics.Finishes,
	trail = Cosmetics.Trails,
	glow = Cosmetics.Glows,
} :: any

Cosmetics.KindOrder = { "palette", "finish", "trail", "glow" }

return Cosmetics
