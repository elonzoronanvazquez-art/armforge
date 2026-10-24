--!strict
-- DUSTWAKE RUINS (biome 6): the forgotten desert. Rolling dunes bury an ancient civilisation: a temple whose back half is under the
-- hill and whose door is the Sunken Seal, a colossus head and hand rising out of the sand, a stepped pyramid with only its top tiers
-- showing, leaning obelisks, broken arches and column drums half sunk in the dunes, a courtyard of crumbled walls and a giant ribcage.
-- Everything "buried" is real geometry placed below the terrain surface, so the dunes hide it and the sand-line cuts it.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local IslandConfig = require(Shared.Config.Islands)
local Build = require(script.Parent.Parent.Build)
local Flora = require(script.Parent.Parent.Flora)
local IslandTerrain = require(script.Parent.Parent.IslandTerrain)
local Forgeheart = require(script.Parent.Forgeheart)

local Dustwake = {}

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles

local DEF = IslandConfig.Defs.Dustwake
local C = DEF.center
local ACCENT = DEF.accent
local GUARDIAN = assert(DEF.guardian, "Dustwake has a guardian")

local SPAWN = V3(C.X, 0, C.Z + 96)
local SKYPORT = V3(C.X - 40, 0, C.Z + 102)
local QUARRY = DEF.fields[1].center
local COURT = DEF.fields[2].center
local SEAL = GUARDIAN.position
local TEMPLE = V3(SEAL.X - 40, 0, SEAL.Z) -- the door faces +X, toward the seal
local COLOSSUS = V3(C.X + 78, 0, C.Z + 22)
local PYRAMID = V3(C.X + 105, 0, C.Z - 95)
local RIBS = V3(C.X - 60, 0, C.Z - 135)
local GATE = V3(C.X, 0, C.Z + 52)

local STONE = Color3.fromRGB(208, 174, 122)
local STONE_D = Color3.fromRGB(170, 134, 92)
local GOLD = Color3.fromRGB(214, 170, 60)
local GLYPH = Color3.fromRGB(120, 240, 255)
local SAND = Color3.fromRGB(214, 184, 128)
local DRY = Color3.fromRGB(150, 146, 80)

local FLOOR_Y = 0.6

function Dustwake.features(): { IslandTerrain.Feature }
	local feats: { IslandTerrain.Feature } = {}
	-- keep the dunes off the flat working areas
	local keepClear: { { pos: Vector3, radius: number } } = {
		{ pos = SPAWN, radius = 66 },
		{ pos = SKYPORT, radius = 40 },
		{ pos = QUARRY, radius = 60 },
		{ pos = COURT, radius = 56 },
		{ pos = SEAL, radius = 44 },
		{ pos = GATE, radius = 30 },
	}
	for i = 1, 22 do
		local a = Build.hash(i, 1) * math.pi * 2
		local r = 30 + Build.hash(i, 2) * 130
		local pos = V3(C.X + math.cos(a) * r, 0, C.Z + math.sin(a) * r)
		local ok = true
		for _, k in keepClear do
			if (pos - k.pos).Magnitude < k.radius + 30 then
				ok = false
				break
			end
		end
		if ok then
			table.insert(feats, { kind = "hill", pos = pos, radius = 36 + Build.hash(i, 3) * 34, height = 7 + Build.hash(i, 4) * 12 })
		end
	end
	-- long dune crests
	table.insert(feats, { kind = "ridge", pos = V3(C.X - 30, 0, C.Z - 62), radius = 24, height = 10, angle = 0.5, length = 150 })
	table.insert(feats, { kind = "ridge", pos = V3(C.X + 62, 0, C.Z + 44), radius = 22, height = 9, angle = -0.7, length = 130 })
	table.insert(feats, { kind = "ridge", pos = V3(C.X - 112, 0, C.Z + 112), radius = 22, height = 9, angle = 0.2, length = 120 })
	-- the dunes that bury things
	table.insert(feats, { kind = "hill", pos = V3(TEMPLE.X - 30, 0, TEMPLE.Z), radius = 66, height = 26 })
	table.insert(feats, { kind = "hill", pos = V3(TEMPLE.X + 4, 0, TEMPLE.Z - 56), radius = 38, height = 14 })
	table.insert(feats, { kind = "hill", pos = V3(TEMPLE.X + 4, 0, TEMPLE.Z + 56), radius = 38, height = 14 })
	table.insert(feats, { kind = "hill", pos = COLOSSUS, radius = 40, height = 10 })
	table.insert(feats, { kind = "hill", pos = PYRAMID, radius = 66, height = 20 })
	table.insert(feats, { kind = "hill", pos = RIBS, radius = 30, height = 7 })
	-- flat areas last so they override any dune that wandered in
	table.insert(feats, { kind = "flat", pos = SPAWN, radius = 66, target = FLOOR_Y, material = Enum.Material.Sand })
	table.insert(feats, { kind = "flat", pos = QUARRY, radius = 60, target = FLOOR_Y, material = Enum.Material.Sand })
	table.insert(feats, { kind = "flat", pos = COURT, radius = 52, target = FLOOR_Y, material = Enum.Material.Sandstone })
	table.insert(feats, { kind = "flat", pos = SEAL, radius = 40, target = FLOOR_Y, material = Enum.Material.Sandstone })
	table.insert(feats, { kind = "flat", pos = GATE, radius = 26, target = FLOOR_Y, material = Enum.Material.Sand })
	return feats
end

-- building blocks ---------------------------------------------------------------------------------------------------------------

local function groundAt(x: number, z: number): number
	return Build.groundY(x, z) or FLOOR_Y
end

local function stone(parent: Instance, name: string, size: Vector3, cf: CFrame, tone: number?): BasePart
	return Build.part(parent, { name = name, size = size, cf = cf, color = STONE:Lerp(STONE_D, math.clamp(tone or 0, 0, 1)), material = Enum.Material.Sandstone, collide = true })
end

local function glyphs(parent: Instance, cf: CFrame, height: number, seed: number, light: boolean)
	-- a column of short neon dashes: the hieroglyphs that still glow after the sand took the rest
	local n = math.max(2, math.floor(height / 2.6))
	for k = 1, n do
		local w = 0.9 + Build.hash(seed, k) * 1.5
		local g = Build.part(parent, { name = "Glyph", size = V3(w, 0.5, 0.22), cf = cf * CF((Build.hash(seed, 20 + k) - 0.5) * 0.8, -height / 2 + k * (height / (n + 1)), 0), color = GLYPH, neon = true })
		if light and k == 1 then
			Build.light(g, GLYPH, 0.4, 10)
		end
	end
end

-- state: full | broken | stump
local function column(parent: Instance, base: Vector3, h: number, d: number, seed: number, state: string)
	local tone = Build.hash(seed, 1) * 0.6
	local height = if state == "stump" then h * 0.35 else if state == "broken" then h * 0.7 else h
	Build.part(parent, { name = "Column", size = V3(height, d, d), cf = CF(base + V3(0, height / 2, 0)) * ANG(0, 0, math.pi / 2), color = STONE:Lerp(STONE_D, tone), material = Enum.Material.Sandstone, shape = "Cylinder", collide = true })
	stone(parent, "Plinth", V3(d * 1.5, d * 0.5, d * 1.5), CF(base + V3(0, d * 0.25, 0)), tone)
	if state == "full" then
		stone(parent, "Capital", V3(d * 1.5, d * 0.5, d * 1.5), CF(base + V3(0, height - d * 0.1, 0)), tone)
		stone(parent, "Abacus", V3(d * 1.9, d * 0.4, d * 1.9), CF(base + V3(0, height + d * 0.3, 0)), tone)
	elseif state == "broken" then
		Build.part(parent, { name = "Break", size = V3(d, d * 0.9, d), cf = CF(base + V3(0, height + d * 0.3, 0)) * ANG(0.5, Build.hash(seed, 2) * 6, 0.35), color = STONE:Lerp(STONE_D, tone), material = Enum.Material.Sandstone, shape = "Wedge" })
	end
	if state ~= "stump" and Build.hash(seed, 3) > 0.35 then
		glyphs(parent, CF(base + V3(0, height / 2, 0)) * ANG(0, Build.hash(seed, 4) * 6, 0) * CF(0, 0, -d / 2 - 0.05), height * 0.8, seed, false)
	end
end

local function drum(parent: Instance, pos: Vector3, len: number, d: number, yaw: number, sink: number)
	Build.part(parent, { name = "ColumnDrum", size = V3(len, d, d), cf = CF(pos + V3(0, d / 2 - sink, 0)) * ANG(0, yaw, (Build.hash(yaw * 10, 1) - 0.5) * 0.25), color = STONE:Lerp(STONE_D, Build.hash(yaw * 7, 2) * 0.6), material = Enum.Material.Sandstone, shape = "Cylinder", collide = true })
end

-- a crumbling wall: a row of blocks of uneven height, half of them lower than the rest
local function wall(parent: Instance, from: Vector3, yaw: number, length: number, height: number, seed: number, sink: number)
	local cf = CF(from) * ANG(0, yaw, 0)
	local x = 0
	local i = 0
	while x < length do
		i += 1
		local w = 3 + Build.hash(seed, i) * 3.5
		local h = height * (0.35 + Build.hash(seed, 100 + i) * 0.65)
		if Build.hash(seed, 200 + i) > 0.82 then
			x += w * 1.4 -- a gap where the wall fell
		else
			local at = (cf * CF(x + w / 2, h / 2 - sink, 0)).Position
			stone(parent, "WallBlock", V3(w, h, 2.6), CF(at) * ANG(0, yaw, (Build.hash(seed, 300 + i) - 0.5) * 0.06), Build.hash(seed, 400 + i) * 0.7)
			if Build.hash(seed, 500 + i) > 0.7 and h > height * 0.6 then
				glyphs(parent, cf * CF(x + w / 2, h / 2 - sink, -1.4) * ANG(0, math.pi, 0), h * 0.7, seed + i, false)
			end
			x += w + 0.1
		end
	end
end

-- a free-standing arch; `sink` buries its feet, `fallen` drops the lintel on the sand
local function arch(parent: Instance, base: Vector3, yaw: number, width: number, height: number, seed: number, sink: number, fallen: boolean)
	local cf = CF(base + V3(0, -sink, 0)) * ANG(0, yaw, 0)
	for _, dx in { -width / 2, width / 2 } do
		stone(parent, "ArchPier", V3(3.2, height, 3.2), cf * CF(dx, height / 2, 0), Build.hash(seed, 1) * 0.5)
		stone(parent, "ArchCap", V3(4, 1.2, 4), cf * CF(dx, height + 0.4, 0), Build.hash(seed, 2) * 0.5)
	end
	if fallen then
		stone(parent, "FallenLintel", V3(width + 3, 2.6, 3.4), cf * CF(width * 0.2, 1.1, 5.5) * ANG(0, 0.5, 0.12), 0.4)
	else
		stone(parent, "Lintel", V3(width + 3.4, 2.6, 3.6), cf * CF(0, height + 1.9, 0), 0.3)
		glyphs(parent, cf * CF(0, height + 1.9, -1.9), 2.4, seed + 5, true)
	end
end

local function obelisk(parent: Instance, base: Vector3, height: number, seed: number, broken: boolean)
	local yaw = Build.hash(seed, 1) * math.pi
	local lean = (Build.hash(seed, 2) - 0.5) * 0.18
	local cf = CF(base + V3(0, -3, 0)) * ANG(0, yaw, lean)
	stone(parent, "ObeliskBase", V3(5.6, 2.4, 5.6), cf * CF(0, 1.2, 0), 0.5)
	local h = if broken then height * 0.62 else height
	stone(parent, "ObeliskShaft", V3(3.6, h, 3.6), cf * CF(0, 2.4 + h / 2, 0), 0.2)
	if not broken then
		Build.part(parent, { name = "Pyramidion", size = V3(3.8, 3.4, 3.8), cf = cf * CF(0, 2.4 + h + 1.7, 0), color = GOLD, material = Enum.Material.Metal, shape = "Wedge", collide = true })
		Build.part(parent, { name = "PyramidionB", size = V3(3.8, 3.4, 3.8), cf = cf * CF(0, 2.4 + h + 1.7, 0) * ANG(0, math.pi, 0), color = GOLD, material = Enum.Material.Metal, shape = "Wedge", collide = true })
	else
		local tip = stone(parent, "FallenTip", V3(3.4, height * 0.36, 3.4), CF(base + V3(5, 1.6, 4)) * ANG(1.35, yaw + 0.6, 0), 0.4)
		tip.CanCollide = true
	end
	glyphs(parent, cf * CF(0, 2.4 + h / 2, -1.85), h * 0.8, seed, true)
	glyphs(parent, cf * CF(0, 2.4 + h / 2, 1.85) * ANG(0, math.pi, 0), h * 0.8, seed + 9, false)
end

-- Temple: pylons, a sealed doorway, a colonnade; the back half is under the dune ---------------------------------------------------

local function buildTemple(parent: Instance)
	local m = Build.model(parent, "BuriedTemple")
	local f = CF(TEMPLE.X, FLOOR_Y, TEMPLE.Z) * ANG(0, math.pi / 2, 0) -- local +Z points at the seal (world +X)
	-- stairs from the court up to the temple floor
	for i = 0, 4 do
		stone(m, "Step", V3(58 - i * 2, 1.2, 4.4), f * CF(0, 0.6 + i * 0.9, 24 - i * 4.4), 0.3 + i * 0.05)
	end
	stone(m, "TempleFloor", V3(60, 1.4, 36), f * CF(0, 4.4, -2), 0.35)
	-- pylons either side of the doorway, taller on the right (the left has half collapsed)
	stone(m, "PylonL", V3(20, 20, 12), f * CF(-19, 14.4, 2), 0.3)
	stone(m, "PylonR", V3(20, 26, 12), f * CF(19, 17.4, 2), 0.2)
	stone(m, "PylonLTop", V3(20, 5, 12), f * CF(-21, 27.2, 2) * ANG(0.05, 0, -0.22), 0.5)
	stone(m, "Lintel", V3(21, 5, 12), f * CF(0, 25, 2), 0.25)
	stone(m, "LintelBroken", V3(10, 3.4, 12), f * CF(-8, 29.6, 2) * ANG(0, 0, -0.5), 0.55)
	-- the sealed door: dark panel, glowing seams, and two golden bars
	stone(m, "DoorFrame", V3(20, 20.2, 11), f * CF(0, 14.6, 1.6), 0.7)
	local door = Build.part(m, { name = "Door", size = V3(15, 17, 1.2), cf = f * CF(0, 13.4, 7.5), color = Color3.fromRGB(26, 32, 44), material = Enum.Material.Slate, collide = true })
	Build.light(door, GLYPH, 0.6, 24)
	for k = -1, 1 do
		Build.part(m, { name = "DoorSeam", size = V3(0.4, 15, 0.3), cf = f * CF(k * 4.6, 13.4, 8.2), color = GLYPH, neon = true })
	end
	for _, y in { 8, 17 } do
		Build.part(m, { name = "DoorBar", size = V3(15.4, 1, 1.4), cf = f * CF(0, y, 8.3), color = GOLD, material = Enum.Material.Metal })
	end
	-- glyph columns on the pylon faces
	for k, x in { -23, -15, 15, 23 } do
		glyphs(m, f * CF(x, 14, 8.1) * ANG(0, math.pi, 0), 17, 40 + k, k % 2 == 0)
	end
	-- the colonnade in front of the pylons
	local states = { "full", "broken", "full", "stump", "broken", "full" }
	for k = 0, 5 do
		local x = -25 + k * 10
		local base = (f * CF(x, 4.4, 15)).Position
		column(m, V3(base.X, base.Y, base.Z), 15, 3.2, 60 + k, states[k + 1])
		if states[k + 1] ~= "full" then
			local fp = (f * CF(x + 4, 0, 22)).Position
			drum(m, V3(fp.X, groundAt(fp.X, fp.Z), fp.Z), 5, 2.8, k * 0.9, 0.6)
		end
	end
	-- side walls running back into the dune, and sand drifted up against the front
	wall(m, (f * CF(-30, 4.4, 8)).Position, math.pi, 34, 12, 71, 0.4)
	wall(m, (f * CF(30, 4.4, 8)).Position, math.pi, 34, 12, 72, 0.4)
	for k = 0, 5 do
		local x = -30 + k * 12
		local p = (f * CF(x, 0, 26 + Build.hash(k, 3) * 3)).Position
		Build.part(m, { name = "Drift", size = V3(12, 3.4, 6), cf = CF(p.X, groundAt(p.X, p.Z) + 0.6, p.Z) * ANG(0, math.pi / 2 + (Build.hash(k, 4) - 0.5) * 0.4, 0), color = SAND, material = Enum.Material.Sand, shape = "Wedge" })
	end
	Build.sign(m, "THE SUNKEN TEMPLE", f * CF(19, 23, 8.4) * ANG(0, math.pi, 0), V3(17, 3, 0.5), Color3.fromRGB(46, 38, 28), Color3.fromRGB(255, 232, 170))
end

-- Seal ring: broken pillars round the Sunken Seal ------------------------------------------------------------------------------------

local function buildSealRing(parent: Instance)
	local m = Build.model(parent, "SealRing")
	local gy = groundAt(SEAL.X, SEAL.Z)
	local states = { "full", "broken", "stump", "full", "broken", "stump", "full", "broken" }
	for i = 0, 7 do
		local a = (i / 8) * math.pi * 2 + 0.3
		local p = V3(SEAL.X + math.cos(a) * 25, 0, SEAL.Z + math.sin(a) * 25)
		-- the pillars on the temple side are mostly buried
		local buried = if p.X < TEMPLE.X + 14 then 3 else 0.4
		column(m, V3(p.X, groundAt(p.X, p.Z) - buried, p.Z), 14, 3, 90 + i, states[i + 1])
	end
	for k = 1, 4 do
		local a = Build.hash(k, 7) * math.pi * 2
		drum(m, V3(SEAL.X + math.cos(a) * 30, gy, SEAL.Z + math.sin(a) * 30), 5, 2.8, a, 0.6)
	end
	-- a glowing sun-disc ring in the floor round the seal
	Build.disc(m, "SunRing", V3(SEAL.X, gy + 0.05, SEAL.Z), 30, 0.14, { color = GOLD, material = Enum.Material.Metal })
	Build.disc(m, "SunFloor", V3(SEAL.X, gy + 0.1, SEAL.Z), 29, 0.14, { color = STONE_D, material = Enum.Material.Sandstone })
	Build.disc(m, "GlyphRing", V3(SEAL.X, gy + 0.16, SEAL.Z), 24, 0.14, { color = GLYPH, neon = true })
	Build.disc(m, "GlyphFloor", V3(SEAL.X, gy + 0.2, SEAL.Z), 23.2, 0.14, { color = STONE_D, material = Enum.Material.Sandstone })
	Build.sign(m, "OSZARAK'S TOMB", CF(SEAL.X + 34, gy + 6.5, SEAL.Z) * ANG(0, -math.pi / 2, 0), V3(16, 2.2, 0.4), Color3.fromRGB(46, 38, 28), Color3.fromRGB(255, 232, 170))
	Build.part(m, { name = "TombPostA", size = V3(0.6, 6.4, 0.6), cf = CF(SEAL.X + 34, gy + 3.2, SEAL.Z - 6), color = STONE_D, material = Enum.Material.Sandstone })
	Build.part(m, { name = "TombPostB", size = V3(0.6, 6.4, 0.6), cf = CF(SEAL.X + 34, gy + 3.2, SEAL.Z + 6), color = STONE_D, material = Enum.Material.Sandstone })
end

-- Colossus: a head and a hand rising out of the dune ---------------------------------------------------------------------------------

local function buildColossus(parent: Instance)
	local m = Build.model(parent, "SunkenColossus")
	local gy = groundAt(COLOSSUS.X, COLOSSUS.Z)
	local face = (V3(SPAWN.X, 0, SPAWN.Z) - V3(COLOSSUS.X, 0, COLOSSUS.Z)).Unit
	local base = V3(COLOSSUS.X, gy - 7, COLOSSUS.Z)
	local f = CFrame.lookAt(base, base + face) -- local -Z is the face
	stone(m, "Neck", V3(12, 8, 12), f * CF(0, 4, 0.5), 0.5)
	stone(m, "Head", V3(15, 17, 14), f * CF(0, 14, 0), 0.15)
	stone(m, "Headdress", V3(20, 6, 17), f * CF(0, 24, 0.4), 0.3)
	stone(m, "HeaddressCrown", V3(8, 5, 9), f * CF(0, 29, 0.6), 0.25)
	for _, dx in { -9.4, 9.4 } do
		stone(m, "Lappet", V3(4, 15, 11), f * CF(dx, 13, 2), 0.35)
	end
	stone(m, "Brow", V3(14, 2, 2.4), f * CF(0, 18.4, -7.4), 0.4)
	Build.part(m, { name = "Nose", size = V3(3.2, 6.5, 4), cf = f * CF(0, 13.8, -8.4) * ANG(math.rad(-8), math.pi, 0), color = STONE:Lerp(STONE_D, 0.15), material = Enum.Material.Sandstone, shape = "Wedge", collide = true })
	stone(m, "Mouth", V3(6.4, 1.4, 1.4), f * CF(0, 9.4, -7.6), 0.75)
	stone(m, "Beard", V3(3.6, 5, 3), f * CF(0, 5, -6.6), 0.35)
	for _, dx in { -3.9, 3.9 } do
		local eye = Build.part(m, { name = "Eye", size = V3(3.4, 1, 0.6), cf = f * CF(dx, 16.2, -7.9), color = GLYPH, neon = true })
		Build.light(eye, GLYPH, 0.8, 18)
	end
	-- cracks
	Build.part(m, { name = "Crack", size = V3(0.4, 11, 0.4), cf = f * CF(5.4, 14, -7.3) * ANG(0, 0, 0.18), color = Color3.fromRGB(70, 52, 36) })
	-- the hand, fingers curled out of the sand beside the head
	local hp = V3(COLOSSUS.X + 22, 0, COLOSSUS.Z - 6)
	local hy = groundAt(hp.X, hp.Z)
	local hf = CF(hp.X, hy - 3, hp.Z) * ANG(0, math.rad(-35), 0)
	stone(m, "Palm", V3(10, 6, 12), hf * CF(0, 3, 0), 0.25)
	for k = 0, 3 do
		stone(m, "Finger", V3(2, 2, 9 - (if k == 3 then 2 else 0)), hf * CF(-4 + k * 2.7, 5.2 + math.abs(k - 1.5) * -0.1, -9) * ANG(math.rad(10), 0, 0), 0.3)
	end
	stone(m, "Thumb", V3(2.2, 2.2, 7), hf * CF(6.6, 4.4, -3) * ANG(0, math.rad(40), 0), 0.3)
	stone(m, "Forearm", V3(8, 7, 22), hf * CF(0, 3, 17), 0.35)
end

-- Pyramid: only the top tiers clear the sand ---------------------------------------------------------------------------------------

local function buildPyramid(parent: Instance)
	local m = Build.model(parent, "BuriedPyramid")
	local gy = groundAt(PYRAMID.X, PYRAMID.Z)
	local tiers = 8
	local tierH = 6
	local baseY = gy - 26
	for k = 0, tiers - 1 do
		local w = 44 - k * 5
		stone(m, "Tier", V3(w, tierH, w), CF(PYRAMID.X, baseY + k * tierH + tierH / 2, PYRAMID.Z), 0.1 + k * 0.07)
	end
	local topY = baseY + tiers * tierH
	-- golden capstone and a glowing eye in the tier below
	local cap = Build.part(m, { name = "Capstone", size = V3(8, 6, 8), cf = CF(PYRAMID.X, topY + 3, PYRAMID.Z), color = GOLD, material = Enum.Material.Metal, collide = true })
	Build.light(cap, Color3.fromRGB(255, 220, 130), 1.4, 60)
	for _, a in { 0, math.pi / 2, math.pi, math.pi * 1.5 } do
		local w = 44 - (tiers - 1) * 5
		local eye = Build.part(m, { name = "PyramidGlyph", size = V3(1.2, 3.6, 0.3), cf = CF(PYRAMID.X, topY - tierH / 2, PYRAMID.Z) * ANG(0, a, 0) * CF(0, 0, -(w / 2 + 0.2)), color = GLYPH, neon = true })
		Build.light(eye, GLYPH, 0.4, 12)
	end
	-- sand spilling down the lower visible tiers
	for k = 1, 5 do
		local a = Build.hash(k, 21) * math.pi * 2
		local p = V3(PYRAMID.X + math.cos(a) * 20, 0, PYRAMID.Z + math.sin(a) * 20)
		Build.part(m, { name = "Drift", size = V3(14, 5, 8), cf = CF(p.X, groundAt(p.X, p.Z) + 1.2, p.Z) * ANG(0, a, 0), color = SAND, material = Enum.Material.Sand, shape = "Wedge" })
	end
end

-- Court: crumbled walls, an altar with a glowing basin ------------------------------------------------------------------------------

local function buildCourt(parent: Instance)
	local m = Build.model(parent, "RuinCourt")
	local w, d = 74, 54
	local corner = V3(COURT.X - w / 2, FLOOR_Y, COURT.Z - d / 2)
	wall(m, corner, 0, w, 11, 301, 0.3)
	wall(m, V3(corner.X, FLOOR_Y, corner.Z + d), 0, w, 11, 302, 0.3)
	wall(m, corner, -math.pi / 2, d, 11, 303, 0.3)
	wall(m, V3(corner.X + w, FLOOR_Y, corner.Z), -math.pi / 2, d, 11, 304, 0.3)
	-- the dry fountain
	local gy = FLOOR_Y
	Build.disc(m, "BasinRim", V3(COURT.X, gy, COURT.Z), 14, 2.2, { color = STONE_D, material = Enum.Material.Sandstone, collide = true })
	Build.disc(m, "BasinFloor", V3(COURT.X, gy + 1.2, COURT.Z), 11.6, 1.2, { color = SAND, material = Enum.Material.Sand })
	local core = Build.pillar(m, "BasinCrystal", V3(COURT.X, gy + 1.6, COURT.Z), 2.4, 7, { color = GLYPH, neon = true, transparency = 0.25 })
	Build.light(core, GLYPH, 0.9, 24)
	Build.emitter(core, {
		Rate = 8,
		Lifetime = NumberRange.new(2, 3.5),
		Speed = NumberRange.new(1, 2.5),
		SpreadAngle = Vector2.new(60, 60),
		Color = ColorSequence.new(GLYPH),
		LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
		Acceleration = Vector3.new(0, 2, 0),
		EmissionDirection = Enum.NormalId.Top,
	})
	-- columns along the north side
	for k = 0, 4 do
		local x = COURT.X - 28 + k * 14
		column(m, V3(x, gy, COURT.Z - 18), 13, 2.8, 120 + k, if k % 2 == 0 then "full" else "broken")
	end
end

-- The rest of the ruins and the dry flora ---------------------------------------------------------------------------------------------

local function buildScatter(parent: Instance)
	local m = Build.model(parent, "Ruins")
	local avoid: { Flora.Zone } = {
		{ pos = SPAWN, radius = 72 },
		{ pos = SKYPORT, radius = 40 },
		{ pos = QUARRY, radius = 58 },
		{ pos = COURT, radius = 56 },
		{ pos = SEAL, radius = 44 },
		{ pos = TEMPLE, radius = 36 },
		{ pos = COLOSSUS, radius = 30 },
		{ pos = PYRAMID, radius = 46 },
		{ pos = GATE, radius = 28 },
	}
	-- leaning obelisks
	Flora.scatter({
		center = C, radius = 175, count = 9, seed = 1100, minY = 0.2, maxY = 30, avoid = avoid, spacing = 40,
		make = function(pos, i, rnd)
			obelisk(m, pos, 14 + rnd * 10, i, i % 3 == 0)
		end,
	})
	-- broken arches, each half sunk
	Flora.scatter({
		center = C, radius = 170, count = 8, seed = 1200, minY = 0.2, maxY = 30, avoid = avoid, spacing = 45,
		make = function(pos, i, rnd)
			arch(m, pos, rnd * math.pi, 10 + rnd * 4, 13 + rnd * 4, i, 3 + rnd * 4, i % 2 == 0)
		end,
	})
	-- fallen column drums and standing columns half buried
	Flora.scatter({
		center = C, radius = 180, count = 22, seed = 1300, minY = 0.2, maxY = 30, avoid = avoid, spacing = 14,
		make = function(pos, i, rnd)
			drum(m, pos, 5 + rnd * 5, 2.6 + rnd, rnd * math.pi, 0.5 + rnd)
		end,
	})
	Flora.scatter({
		center = C, radius = 175, count = 12, seed = 1400, minY = 0.2, maxY = 30, avoid = avoid, spacing = 22,
		make = function(pos, i, rnd)
			column(m, pos - V3(0, 2 + rnd * 4, 0), 11 + rnd * 4, 2.8, 200 + i, if i % 3 == 0 then "full" else "broken")
		end,
	})
	-- rubble blocks
	Flora.scatter({
		center = C, radius = 185, count = 40, seed = 1500, minY = 0.2, maxY = 30, avoid = avoid, spacing = 8,
		make = function(pos, i, rnd)
			local s = 2 + rnd * 3.4
			stone(m, "Rubble", V3(s, s * 0.7, s * 0.9), CF(pos + V3(0, s * 0.15, 0)) * ANG(rnd, i, rnd * 0.6), rnd)
		end,
	})
	-- the dry flora
	Flora.scatter({
		center = C, radius = 185, count = 36, seed = 1600, minY = 0.2, maxY = 24, avoid = avoid, spacing = 12,
		make = function(pos, i, rnd)
			Flora.cactus(m, pos, 5 + rnd * 6, i)
		end,
	})
	Flora.scatter({
		center = C, radius = 185, count = 12, seed = 1700, minY = 0.2, maxY = 24, avoid = avoid, spacing = 25,
		make = function(pos, i, rnd)
			Flora.deadTree(m, pos, 9 + rnd * 6, i)
		end,
	})
	Flora.scatter({
		center = C, radius = 185, count = 70, seed = 1800, minY = 0.2, maxY = 24, avoid = avoid, spacing = 5,
		make = function(pos, i, rnd)
			Flora.tuft(m, pos, 1.6 + rnd * 1.6, i, DRY)
		end,
	})
	-- layered sandstone mesas along the rim, the island's silhouette
	for i = 1, 5 do
		local a = math.rad(200 + i * 26)
		local x, z = C.X + math.cos(a) * 138, C.Z + math.sin(a) * 138
		local y = Build.groundY(x, z)
		local here = V3(x, 0, z)
		if y and (here - COURT).Magnitude > 62 and (here - PYRAMID).Magnitude > 56 and (here - RIBS).Magnitude > 44 and (here - QUARRY).Magnitude > 66 then
			local w = 16 + Build.hash(i, 5) * 12
			local yy = y - 3
			for layer = 0, 2 do
				local s = w * (1 - layer * 0.18)
				local h = 9 + Build.hash(i, 6 + layer) * 6
				stone(m, "Mesa", V3(s, h, s * 0.85), CF(x, yy + h / 2, z) * ANG(0, a + layer * 0.2, 0), 0.1 + layer * 0.3)
				yy += h
			end
		end
	end
	-- giant ribcage half in the sand
	local rb = Build.model(m, "Ribcage")
	local ry = groundAt(RIBS.X, RIBS.Z)
	Build.part(rb, { name = "Spine", size = V3(34, 2, 2), cf = CF(RIBS.X, ry + 0.6, RIBS.Z) * ANG(0, 0.35, 0), color = Color3.fromRGB(226, 214, 190), material = Enum.Material.Marble, shape = "Cylinder", collide = true })
	for k = 0, 6 do
		local along = -13 + k * 4.4
		local at = CF(RIBS.X, ry - 1, RIBS.Z) * ANG(0, 0.35, 0) * CF(along, 0, 0)
		local radius = 9 - math.abs(k - 3) * 0.9
		for seg = 0, 5 do
			local a1, a2 = math.rad(seg * 30), math.rad((seg + 1) * 30)
			local p1 = V3(0, math.sin(a1) * radius, math.cos(a1) * radius)
			local p2 = V3(0, math.sin(a2) * radius, math.cos(a2) * radius)
			for _, side in { 1, -1 } do
				local q1, q2 = V3(0, p1.Y, p1.Z * side), V3(0, p2.Y, p2.Z * side)
				Build.part(rb, { name = "Rib", size = V3(0.9, 0.9, (q2 - q1).Magnitude + 0.2), cf = CFrame.lookAt((at * CF(q1)).Position:Lerp((at * CF(q2)).Position, 0.5), (at * CF(q2)).Position), color = Color3.fromRGB(226, 214, 190), material = Enum.Material.Marble, collide = seg < 2 })
			end
		end
	end
	-- wisps of wind-blown sand
	for i = 1, 10 do
		local x, z = C.X + (Build.hash(i, 41) - 0.5) * 300, C.Z + (Build.hash(i, 42) - 0.5) * 300
		local y = Build.groundY(x, z)
		if y then
			local box = Build.part(m, { name = "SandWisp", size = V3(44, 5, 44), cf = CF(x, y + 3, z), transparency = 1 })
			Build.emitter(box, {
				Rate = 5,
				Lifetime = NumberRange.new(5, 8),
				Speed = NumberRange.new(6, 11),
				SpreadAngle = Vector2.new(12, 12),
				Color = ColorSequence.new(Color3.fromRGB(232, 206, 156)),
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 10) }),
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(0.4, 0.78), NumberSequenceKeypoint.new(1, 1) }),
				Acceleration = Vector3.new(3, 0.4, 0),
				EmissionDirection = Enum.NormalId.Right,
			})
		end
	end
end

-- Entrance and field signs ---------------------------------------------------------------------------------------------------------

local function buildGate(parent: Instance)
	local m = Build.model(parent, "SandGate")
	local gy = groundAt(GATE.X, GATE.Z)
	arch(m, V3(GATE.X, gy, GATE.Z), 0, 26, 17, 77, 0.5, false)
	Build.sign(m, "DUSTWAKE RUINS", CF(GATE.X, gy + 14, GATE.Z - 2.2), V3(20, 2.8, 0.5), Color3.fromRGB(46, 38, 28), Color3.fromRGB(255, 232, 170))
	-- note: the sign faces -Z, i.e. back toward the dunes; the front (spawn) side gets a second one
	Build.sign(m, "DUSTWAKE RUINS", CF(GATE.X, gy + 14, GATE.Z + 2.2) * ANG(0, math.pi, 0), V3(20, 2.8, 0.5), Color3.fromRGB(46, 38, 28), Color3.fromRGB(255, 232, 170))
	column(m, V3(GATE.X - 24, gy, GATE.Z + 6), 12, 3, 78, "broken")
	column(m, V3(GATE.X + 24, gy, GATE.Z + 4), 12, 3, 79, "stump")
end

local function signPost(parent: Instance, text: string, pos: Vector3)
	local gy = groundAt(pos.X, pos.Z)
	for _, dx in { -5.5, 5.5 } do
		stone(parent, "SignPillar", V3(1.4, 8, 1.4), CF(pos.X + dx, gy + 3.6, pos.Z), 0.5)
	end
	Build.sign(parent, text, CF(pos.X, gy + 7, pos.Z + 0.2) * ANG(0, math.pi, 0), V3(13, 2.4, 0.5), Color3.fromRGB(46, 38, 28), Color3.fromRGB(255, 232, 170))
end

function Dustwake.build(folder: Folder, ctx: any)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "DustwakeSpawn"
	spawn.Anchored = true
	spawn.Size = V3(12, 1, 12)
	spawn.CFrame = CF(V3(SPAWN.X, 1.1, SPAWN.Z))
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Material = Enum.Material.Sandstone
	spawn.Color = Color3.fromRGB(184, 146, 98)
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = folder
	ctx.spawn("Dustwake", spawn)
	Forgeheart.skyport(folder, SKYPORT, "SKYPORT: RETURN", ACCENT, math.rad(200))

	buildGate(folder)
	buildTemple(folder)
	buildSealRing(folder)
	buildColossus(folder)
	buildPyramid(folder)
	buildCourt(folder)
	local signs = Build.model(folder, "FieldSigns")
	signPost(signs, "DUNE QUARRY", V3(QUARRY.X + 8, 0, QUARRY.Z + 58))
	signPost(signs, "RUIN COURT", V3(COURT.X + 8, 0, COURT.Z + 50))
	buildScatter(folder)
end

return Dustwake
