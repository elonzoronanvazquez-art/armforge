--!strict
-- ARMFORGE UI design tokens: a warm "forge at dusk" palette (charcoal metal, copper strokes, ember accent).
-- Every UI module takes its colours, fonts and sizes from here so the interface stays one consistent system.

local Theme = {}

Theme.colors = {
	bg = Color3.fromRGB(20, 18, 26),
	panel = Color3.fromRGB(32, 29, 40),
	panelHi = Color3.fromRGB(46, 42, 56),
	panelLo = Color3.fromRGB(24, 22, 30),
	stroke = Color3.fromRGB(94, 78, 70),
	strokeHi = Color3.fromRGB(196, 130, 78),
	text = Color3.fromRGB(250, 241, 228),
	sub = Color3.fromRGB(176, 166, 168),
	dim = Color3.fromRGB(120, 112, 120),
	accent = Color3.fromRGB(255, 150, 60),
	accentDark = Color3.fromRGB(196, 100, 34),
	good = Color3.fromRGB(110, 224, 136),
	bad = Color3.fromRGB(255, 104, 92),
	warn = Color3.fromRGB(255, 206, 84),
	xp = Color3.fromRGB(110, 196, 255),
	coin = Color3.fromRGB(255, 208, 84),
	shard = Color3.fromRGB(192, 132, 255),
	black = Color3.fromRGB(10, 8, 14),
}

Theme.font = Enum.Font.GothamMedium
Theme.fontBold = Enum.Font.GothamBold
Theme.fontBlack = Enum.Font.GothamBlack

Theme.radius = UDim.new(0, 8)
Theme.radiusLg = UDim.new(0, 12)

-- Design-space size the UI is authored in (scaled to the real viewport by UI.luau).
Theme.designSize = Vector2.new(1280, 720)

Theme.rarity = {
	Common = Color3.fromRGB(200, 205, 212),
	Uncommon = Color3.fromRGB(120, 220, 130),
	Rare = Color3.fromRGB(90, 170, 255),
	Epic = Color3.fromRGB(190, 110, 255),
	Legendary = Color3.fromRGB(255, 184, 56),
} :: { [string]: Color3 }

return Theme
