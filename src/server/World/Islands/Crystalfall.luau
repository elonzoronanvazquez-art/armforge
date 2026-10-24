--!strict
-- FROSTPEAK MOUNTAIN (internal id Crystalfall, biome 3): a huge flat-topped snow mountain. Singing crystal arch at the foot, snowy pines
-- on the lower slopes, snow-capped quartz / amethyst / Heartstone rocks at the Snowdrift Meadow and on the Crystal Ledge terrace, a
-- switchback road that spirals to the summit, and the Frozen Chorus's seal on the summit under pillars of light.
-- An aerial tramway (stations, towers, cable and a parked gondola) is built as scenery; it does not carry anyone yet (docs/NEXT.md).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local IslandConfig = require(Shared.Config.Islands)
local Build = require(script.Parent.Parent.Build)
local Flora = require(script.Parent.Parent.Flora)
local IslandTerrain = require(script.Parent.Parent.IslandTerrain)
local Forgeheart = require(script.Parent.Forgeheart)

local Crystalfall = {}

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles

local DEF = IslandConfig.Defs.Crystalfall
local C = DEF.center
local ACCENT = DEF.accent
local GUARDIAN = assert(DEF.guardian, "Crystalfall has a guardian")

local MOUNTAIN = V3(GUARDIAN.position.X, 0, GUARDIAN.position.Z) -- the summit is the centre
local MOUNTAIN_RADIUS = 118
local SUMMIT_RADIUS = 24
local MOUNTAIN_HEIGHT = 94
local SPAWN = V3(C.X, 0, C.Z + 96)
local SKYPORT = V3(C.X + 38, 0, C.Z + 100)
local ARCH = V3(C.X, 0, C.Z + 62)
local MEADOW = DEF.fields[1].center
local LEDGE = DEF.fields[2].center
local BASE_STATION = V3(C.X + 95, 0, C.Z + 60)
local SUMMIT_STATION = V3(MOUNTAIN.X + 30, 0, MOUNTAIN.Z)
local LEDGE_HEIGHT = 22

local SNOW = Color3.fromRGB(240, 246, 252)
local ICE = Color3.fromRGB(176, 218, 240)
local STEEL = Color3.fromRGB(90, 100, 130)
local DARK = Color3.fromRGB(34, 42, 62)

function Crystalfall.features(): { IslandTerrain.Feature }
	return {
		{ kind = "mound", pos = MOUNTAIN, radius = MOUNTAIN_RADIUS, height = MOUNTAIN_HEIGHT, length = SUMMIT_RADIUS },
		{ kind = "hill", pos = V3(C.X + 120, 0, C.Z + 30), radius = 34, height = 9 },
		{ kind = "hill", pos = V3(C.X - 120, 0, C.Z + 90), radius = 30, height = 8 },
		{ kind = "ridge", pos = V3(C.X, 0, C.Z - 168), radius = 24, height = 20, angle = 0, length = 140 },
		-- flat working areas last, so they override the mountain's flanks
		{ kind = "flat", pos = SPAWN, radius = 50, target = 0.6, material = Enum.Material.Limestone },
		{ kind = "flat", pos = ARCH, radius = 22, target = 0.6, material = Enum.Material.Snow },
		{ kind = "flat", pos = BASE_STATION, radius = 24, target = 0.6, material = Enum.Material.Limestone },
		{ kind = "flat", pos = MEADOW, radius = 56, target = 0.6, material = Enum.Material.Snow },
		{ kind = "flat", pos = LEDGE, radius = 40, target = LEDGE_HEIGHT, material = Enum.Material.Limestone },
		{ kind = "flat", pos = MOUNTAIN, radius = 28, target = MOUNTAIN_HEIGHT + 0.6, material = Enum.Material.Snow },
	}
end

-- helpers ---------------------------------------------------------------------------------------------------------------------------

local function groundAt(x: number, z: number): number
	return Build.groundY(x, z) or 0.6
end

-- a cluster of tall crystal spikes
local function crystalCluster(parent: Instance, pos: Vector3, scale: number, seed: number, color: Color3)
	local m = Build.model(parent, "CrystalCluster")
	local count = 4 + math.floor(Build.hash(seed, 1) * 3)
	for i = 1, count do
		local a = Build.hash(seed, i) * math.pi * 2
		local r = Build.hash(seed, i + 10) * 2.4 * scale
		local h = (4 + Build.hash(seed, i + 20) * 8) * scale
		local w = (1.2 + Build.hash(seed, i + 30) * 1.4) * scale
		local lean = (Build.hash(seed, i + 40) - 0.5) * 0.7
		Build.part(m, {
			name = "Crystal",
			size = V3(w, h, w),
			cf = CF(pos + V3(math.cos(a) * r, h / 2 - 0.4, math.sin(a) * r)) * ANG(lean, a, lean * 0.6),
			color = color:Lerp(Color3.new(1, 1, 1), Build.hash(seed, i + 50) * 0.4),
			material = Enum.Material.Glass,
			transparency = 0.18,
			reflectance = 0.2,
			shape = "Wedge",
		})
		Build.part(m, {
			name = "CrystalCore",
			size = V3(w * 0.5, h * 0.7, w * 0.5),
			cf = CF(pos + V3(math.cos(a) * r, h * 0.4, math.sin(a) * r)) * ANG(lean, a, lean * 0.6),
			color = color,
			neon = true,
			shape = "Wedge",
		})
	end
	return m
end

-- A strip of material laid along the terrain between two points (the road, the cable).
local function strip(parent: Instance, name: string, a: Vector3, b: Vector3, width: number, thick: number, color: Color3, material: Enum.Material, collide: boolean?): BasePart
	local len = (b - a).Magnitude + 0.5
	return Build.part(parent, { name = name, size = V3(width, thick, len), cf = CFrame.lookAt((a + b) / 2, b), color = color, material = material, collide = collide })
end

-- Entrance: the singing arch ------------------------------------------------------------------------------------------------------------

local function buildArch(parent: Instance)
	local arch = Build.model(parent, "SingingArch")
	local archPos = V3(ARCH.X, 0, ARCH.Z)
	local archMesh = Build.mesh(arch, "CrystalArch", CF(archPos), 3.4, false)
	if archMesh then
		archMesh.CFrame = CF(archPos + V3(0, archMesh.Size.Y / 2 - 0.5, 0))
		for _, dx in { -1, 1 } do
			Build.part(arch, { name = "ArchLegCollider", size = V3(archMesh.Size.X * 0.2, archMesh.Size.Y * 0.8, archMesh.Size.Z * 0.5), cf = CF(archPos + V3(dx * archMesh.Size.X * 0.36, archMesh.Size.Y * 0.4, 0)), transparency = 1, collide = true })
		end
		local glow = Build.part(arch, { name = "ArchGlow", size = V3(1, 1, 1), cf = CF(archPos + V3(0, archMesh.Size.Y * 0.55, 0)), transparency = 1 })
		Build.light(glow, ACCENT, 1.4, 60)
	else
		for side = -1, 1, 2 do
			for i = 1, 6 do
				local h = 22 + i * 2.4
				local off = side * (13 + i * 0.5)
				local part = Build.part(arch, {
					name = "ArchCrystal",
					size = V3(4.4 - i * 0.3, h, 4.4 - i * 0.3),
					cf = CF(archPos + V3(off, h / 2 - 1, (i - 3.5) * 2.4)) * ANG(0, side * i * 0.3, -side * 0.22),
					color = Color3.fromRGB(150, 190, 255):Lerp(Color3.fromRGB(200, 150, 255), i / 6),
					material = Enum.Material.Glass,
					transparency = 0.2,
					reflectance = 0.25,
					shape = "Wedge",
					collide = i <= 2,
				})
				if i % 2 == 0 then
					Build.light(part, ACCENT, 0.8, 22)
				end
			end
		end
		local cap = Build.part(arch, { name = "ArchCap", size = V3(34, 3, 5), cf = CF(archPos + V3(0, 34, 0)), color = ACCENT, neon = true, transparency = 0.35 })
		Build.light(cap, ACCENT, 1.4, 60)
	end
	Build.sign(arch, "FROSTPEAK MOUNTAIN", CF(archPos + V3(0, 14, 7)) * ANG(0, math.pi, 0), V3(22, 2.6, 0.5), DARK, Color3.fromRGB(200, 235, 255))
	for _, dx in { -10, 10 } do
		Build.part(arch, { name = "SignPost", size = V3(0.8, 14, 0.8), cf = CF(archPos + V3(dx, 7, 7)), color = STEEL, material = Enum.Material.Metal })
	end
end

-- Summit road: a strip that spirals clockwise from the foot to the summit plateau, with lanterns -----------------------------------------------

local function buildRoad(parent: Instance): { Vector3 }
	local m = Build.model(parent, "SummitRoad")
	local steps = 120
	local turns = 2.2
	local pts: { Vector3 } = {}
	for i = 0, steps do
		local s = i / steps
		local r = (MOUNTAIN_RADIUS - 6) - (MOUNTAIN_RADIUS - 6 - 16) * s
		local theta = math.pi / 2 - math.pi * 2 * turns * s
		local x, z = MOUNTAIN.X + math.cos(theta) * r, MOUNTAIN.Z + math.sin(theta) * r
		table.insert(pts, V3(x, groundAt(x, z) + 0.35, z))
	end
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		strip(m, "RoadSlab", a, b, 6, 0.5, if i % 2 == 0 then Color3.fromRGB(104, 112, 130) else Color3.fromRGB(94, 102, 120), Enum.Material.Slate)
		if i % 6 == 0 then
			local side = (b - a).Unit:Cross(Vector3.yAxis).Unit * 3.8
			local base = a + side
			Build.part(m, { name = "LampPost", size = V3(0.5, 5, 0.5), cf = CF(base + V3(0, 2.5, 0)), color = STEEL, material = Enum.Material.Metal })
			local lamp = Build.part(m, { name = "Lamp", size = V3(1.1, 1.1, 1.1), cf = CF(base + V3(0, 5.4, 0)), color = Color3.fromRGB(150, 220, 255), neon = true, shape = "Ball" })
			Build.light(lamp, Color3.fromRGB(150, 220, 255), 1, 20)
		end
	end
	-- trailhead sign and a distance board every quarter
	local start = pts[1]
	Build.sign(m, "SUMMIT ROAD  ·  THE FROZEN CHORUS", CF(start + V3(-9, 6, 4)) * ANG(0, math.pi, 0), V3(20, 2.4, 0.5), DARK, Color3.fromRGB(200, 235, 255))
	Build.part(m, { name = "TrailPostA", size = V3(0.7, 6, 0.7), cf = CF(start + V3(-17, 3, 4)), color = STEEL, material = Enum.Material.Metal })
	Build.part(m, { name = "TrailPostB", size = V3(0.7, 6, 0.7), cf = CF(start + V3(-1, 3, 4)), color = STEEL, material = Enum.Material.Metal })
	return pts
end

-- Summit: the seal's arena under pillars of light ------------------------------------------------------------------------------------------

local function buildSummit(parent: Instance)
	local m = Build.model(parent, "Summit")
	local gy = groundAt(MOUNTAIN.X, MOUNTAIN.Z)
	Build.disc(m, "IceFloor", V3(MOUNTAIN.X, gy + 0.05, MOUNTAIN.Z), 46, 0.3, { color = ICE, material = Enum.Material.Ice, reflectance = 0.15 })
	Build.disc(m, "RuneRing", V3(MOUNTAIN.X, gy + 0.3, MOUNTAIN.Z), 36, 0.12, { color = Color3.fromRGB(150, 230, 255), neon = true })
	Build.disc(m, "RuneFloor", V3(MOUNTAIN.X, gy + 0.36, MOUNTAIN.Z), 35.2, 0.12, { color = Color3.fromRGB(150, 188, 214), material = Enum.Material.Ice })
	local pal = { Color3.fromRGB(130, 200, 255), Color3.fromRGB(200, 150, 255), Color3.fromRGB(150, 255, 235) }
	for i = 0, 7 do
		local a = (i / 8) * math.pi * 2 + 0.2
		local x, z = MOUNTAIN.X + math.cos(a) * 20, MOUNTAIN.Z + math.sin(a) * 20
		local y = groundAt(x, z)
		crystalCluster(m, V3(x, y, z), 1.9, 300 + i, pal[1 + i % 3])
		if i % 2 == 0 then
			local beam = Build.pillar(m, "ChoirLight", V3(x, y + 6, z), 3, 90, { color = pal[1 + i % 3], neon = true, transparency = 0.8 })
			Build.light(beam, pal[1 + i % 3], 1.2, 40)
		end
	end
	local signY = groundAt(MOUNTAIN.X, MOUNTAIN.Z + 25)
	Build.sign(m, "THE FROZEN CHORUS", CF(MOUNTAIN.X, signY + 8, MOUNTAIN.Z + 25) * ANG(0, math.pi, 0), V3(18, 2.4, 0.5), DARK, Color3.fromRGB(200, 235, 255))
	for _, dx in { -8, 8 } do
		Build.part(m, { name = "SummitPost", size = V3(0.7, 8, 0.7), cf = CF(MOUNTAIN.X + dx, signY + 4, MOUNTAIN.Z + 25), color = STEEL, material = Enum.Material.Metal })
	end
	-- snowfall over the whole mountain
	local sky = Build.part(m, { name = "Snowfall", size = V3(240, 2, 240), cf = CF(MOUNTAIN.X, gy + 70, MOUNTAIN.Z), transparency = 1 })
	Build.emitter(sky, {
		Rate = 60,
		Lifetime = NumberRange.new(16, 22),
		Speed = NumberRange.new(3, 6),
		SpreadAngle = Vector2.new(25, 25),
		Color = ColorSequence.new(Color3.fromRGB(245, 250, 255)),
		LightEmission = 0.3,
		Size = NumberSequence.new(0.45),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.1, 0.1), NumberSequenceKeypoint.new(0.9, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		Acceleration = Vector3.new(1.2, -1, 0.4),
		EmissionDirection = Enum.NormalId.Bottom,
	})
end

-- Aerial tramway: two stations, two towers, a double cable and a parked gondola (scenery) -------------------------------------------------------

local function station(parent: Instance, pos: Vector3, label: string)
	local m = Build.model(parent, "Station")
	local gy = groundAt(pos.X, pos.Z)
	Build.part(m, { name = "Deck", size = V3(18, 1, 14), cf = CF(pos.X, gy + 0.3, pos.Z), color = Color3.fromRGB(70, 80, 104), material = Enum.Material.DiamondPlate, collide = true })
	for _, dx in { -8, 8 } do
		for _, dz in { -6, 6 } do
			Build.part(m, { name = "Pillar", size = V3(1, 14, 1), cf = CF(pos.X + dx, gy + 7.3, pos.Z + dz), color = STEEL, material = Enum.Material.Metal, collide = true })
		end
	end
	Build.part(m, { name = "Roof", size = V3(20, 1, 16), cf = CF(pos.X, gy + 14.8, pos.Z), color = Color3.fromRGB(150, 70, 60), material = Enum.Material.Metal })
	Build.part(m, { name = "Wheel", size = V3(1, 9, 9), cf = CF(pos.X, gy + 11.5, pos.Z), color = DARK, material = Enum.Material.Metal, shape = "Cylinder" })
	Build.sign(m, label, CF(pos.X, gy + 5, pos.Z + 7.2) * ANG(0, math.pi, 0), V3(15, 2, 0.4), DARK, Color3.fromRGB(255, 226, 170))
	return gy + 13
end

local function buildTramway(parent: Instance)
	local m = Build.model(parent, "Tramway")
	local topA = station(m, BASE_STATION, "TRAMWAY  ·  COMING SOON")
	local topB = station(m, SUMMIT_STATION, "SUMMIT STATION")
	local a = V3(BASE_STATION.X, topA, BASE_STATION.Z)
	local b = V3(SUMMIT_STATION.X, topB, SUMMIT_STATION.Z)
	local across = (b - a).Unit:Cross(Vector3.yAxis).Unit * 1.6
	for _, off in { across, -across } do
		strip(m, "Cable", a + off, b + off, 0.3, 0.3, Color3.fromRGB(40, 40, 46), Enum.Material.Metal)
	end
	-- two towers holding the cable up
	for _, f in { 0.34, 0.68 } do
		local p = a:Lerp(b, f)
		local gy = groundAt(p.X, p.Z)
		local top = p.Y + 1.2
		Build.pillar(m, "TowerLeg", V3(p.X, gy - 2, p.Z), 1.6, top - gy + 2, { color = STEEL, material = Enum.Material.Metal, collide = true })
		Build.part(m, { name = "TowerArm", size = V3(5.6, 0.7, 0.7), cf = CFrame.lookAt(V3(p.X, top, p.Z), V3(p.X, top, p.Z) + across.Unit) * ANG(0, math.pi / 2, 0), color = STEEL, material = Enum.Material.Metal })
	end
	-- a parked gondola hanging from the upper cable
	local gp = a:Lerp(b, 0.52) + across
	local yaw = math.atan2(-(b - a).X, -(b - a).Z)
	local cabin = CF(gp + V3(0, -5.2, 0)) * ANG(0, yaw, 0)
	Build.part(m, { name = "Hanger", size = V3(0.3, 3.2, 0.3), cf = CF(gp + V3(0, -1.6, 0)), color = Color3.fromRGB(40, 40, 46), material = Enum.Material.Metal })
	Build.part(m, { name = "Cabin", size = V3(4.4, 3.2, 6), cf = cabin, color = Color3.fromRGB(190, 70, 60), material = Enum.Material.Metal })
	Build.part(m, { name = "CabinRoof", size = V3(4.8, 0.4, 6.4), cf = cabin * CF(0, 1.8, 0), color = Color3.fromRGB(240, 240, 244), material = Enum.Material.Metal })
	for _, dx in { -2.25, 2.25 } do
		Build.part(m, { name = "CabinWindow", size = V3(0.2, 1.4, 4.2), cf = cabin * CF(dx, 0.3, 0), color = Color3.fromRGB(190, 230, 255), neon = true, transparency = 0.3 })
	end
end

-- Flora ---------------------------------------------------------------------------------------------------------------------------------------------

local function buildFlora(parent: Instance, road: { Vector3 })
	local m = Build.model(parent, "Flora")
	local avoid: { Flora.Zone } = {
		{ pos = SPAWN, radius = 62 },
		{ pos = SKYPORT, radius = 40 },
		{ pos = ARCH, radius = 36 },
		{ pos = MEADOW, radius = 56 },
		{ pos = LEDGE, radius = 42 },
		{ pos = BASE_STATION, radius = 30 },
		{ pos = MOUNTAIN, radius = 30 },
	}
	for _, p in road do
		table.insert(avoid, { pos = p, radius = 7 })
	end
	-- pines on the lower slopes, thinning out toward the treeline
	Flora.scatter({
		center = MOUNTAIN, radius = 150, count = 150, seed = 2100, minY = 0.3, maxY = 46, avoid = avoid, spacing = 8,
		make = function(pos, i, rnd)
			Flora.pine(m, pos, 10 + rnd * 12, i, pos.Y > 5)
		end,
	})
	Flora.scatter({
		center = MOUNTAIN, radius = 150, count = 70, seed = 2200, minY = 0.3, maxY = 40, avoid = avoid, spacing = 5,
		make = function(pos, i, rnd)
			Flora.bush(m, pos, 2 + rnd * 1.6, i, { Color3.fromRGB(196, 222, 214), Color3.fromRGB(170, 204, 196), Color3.fromRGB(226, 238, 236) }, nil)
		end,
	})
	-- snow-capped rocks all the way up
	Flora.scatter({
		center = MOUNTAIN, radius = 140, count = 70, seed = 2300, minY = 0.3, maxY = 96, avoid = avoid, spacing = 9,
		make = function(pos, i, rnd)
			Flora.mossRock(m, pos, 3 + rnd * 5, i, Color3.fromRGB(116, 124, 142), SNOW, Enum.Material.Snow)
		end,
	})
	Flora.scatter({
		center = MOUNTAIN, radius = 140, count = 16, seed = 2400, minY = 0.3, maxY = 60, avoid = avoid, spacing = 22,
		make = function(pos, i, rnd)
			local pal = { Color3.fromRGB(130, 200, 255), Color3.fromRGB(200, 150, 255), Color3.fromRGB(150, 255, 235) }
			crystalCluster(m, pos, 0.8 + rnd * 1.1, 400 + i, pal[1 + i % 3])
		end,
	})
	for i = 1, 12 do
		local a = Build.hash(i, 5) * math.pi * 2
		local r = 20 + Build.hash(i, 6) * 80
		Build.part(m, {
			name = "FloatingShard",
			size = V3(1.4, 3.6, 1.4),
			cf = CF(MOUNTAIN.X + math.cos(a) * r, 50 + Build.hash(i, 7) * 60, MOUNTAIN.Z + math.sin(a) * r) * ANG(Build.hash(i, 8), Build.hash(i, 9) * 6, 0.4),
			color = Color3.fromRGB(150, 220, 255),
			neon = true,
			shape = "Wedge",
		})
	end
end

local function signPost(parent: Instance, text: string, x: number, z: number)
	local gy = groundAt(x, z)
	for _, dx in { -5.5, 5.5 } do
		Build.part(parent, { name = "SignPost", size = V3(0.7, 8, 0.7), cf = CF(x + dx, gy + 4, z), color = STEEL, material = Enum.Material.Metal, collide = true })
	end
	Build.sign(parent, text, CF(x, gy + 7, z + 0.2) * ANG(0, math.pi, 0), V3(13, 2.4, 0.5), DARK, Color3.fromRGB(200, 235, 255))
end

function Crystalfall.build(folder: Folder, ctx: any)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "CrystalfallSpawn"
	spawn.Anchored = true
	spawn.Size = V3(12, 1, 12)
	spawn.CFrame = CF(V3(SPAWN.X, 1.1, SPAWN.Z))
	spawn.Neutral = true
	spawn.Enabled = true
	spawn.Duration = 0
	spawn.Material = Enum.Material.Glass
	spawn.Color = Color3.fromRGB(120, 180, 230)
	spawn.Transparency = 0.2
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = folder
	ctx.spawn("Crystalfall", spawn)
	Forgeheart.skyport(folder, SKYPORT, "SKYPORT: RETURN", ACCENT, math.rad(160))

	buildArch(folder)
	local road = buildRoad(folder)
	buildSummit(folder)
	buildTramway(folder)
	local signs = Build.model(folder, "FieldSigns")
	signPost(signs, "SNOWDRIFT MEADOW", MEADOW.X + 6, MEADOW.Z + 52)
	signPost(signs, "CRYSTAL LEDGE", LEDGE.X - 6, LEDGE.Z + 34)
	buildFlora(folder, road)
end

return Crystalfall
