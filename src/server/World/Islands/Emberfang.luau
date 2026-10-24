--!strict
-- EMBERFANG VOLCANO (internal id Emberfang, biome 4; +50% coins and XP): a smoking black cone with a crater lake of lava at the top.
-- Lava rivers run down the flanks into pools, scorched trees and molten rocks dot the slopes, an ember road spirals up to the rim, and the
-- Caldera Seal stands on the crater floor beside the lava lake. Fang spires keep the island's old identity.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local IslandConfig = require(Shared.Config.Islands)
local Build = require(script.Parent.Parent.Build)
local Flora = require(script.Parent.Parent.Flora)
local Road = require(script.Parent.Parent.Road)
local IslandTerrain = require(script.Parent.Parent.IslandTerrain)
local Forgeheart = require(script.Parent.Forgeheart)

local Emberfang = {}

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles

local DEF = IslandConfig.Defs.Emberfang
local C = DEF.center
local ACCENT = DEF.accent
local GUARDIAN = assert(DEF.guardian, "Emberfang has a guardian")

local CRATER = V3(C.X, 0, C.Z - 35) -- the volcano's axis
local CONE_RADIUS = 112
local CONE_HEIGHT = 64
local CRATER_RADIUS = 40
local CRATER_DEPTH = 30
local FLOOR_Y = CONE_HEIGHT + 0.6 - CRATER_DEPTH
local SEAL = V3(GUARDIAN.position.X, 0, GUARDIAN.position.Z)
local LAKE = V3(CRATER.X + 13, 0, CRATER.Z + 5)
local SPAWN = V3(C.X, 0, C.Z + 96)
local SKYPORT = V3(C.X - 38, 0, C.Z + 100)
local GATE = V3(C.X, 0, C.Z + 64)
local FLATS = DEF.fields[1].center
local TERRACE = DEF.fields[2].center
local TERRACE_HEIGHT = 13

local LAVA = Color3.fromRGB(255, 96, 40)
local LAVA_HOT = Color3.fromRGB(255, 190, 70)
local BASALT = Color3.fromRGB(28, 26, 32)
local IRON = Color3.fromRGB(50, 40, 44)

function Emberfang.features(): { IslandTerrain.Feature }
	return {
		{ kind = "mound", pos = CRATER, radius = CONE_RADIUS, height = CONE_HEIGHT, length = 26 },
		{ kind = "pit", pos = CRATER, radius = CRATER_RADIUS, height = CRATER_DEPTH },
		{ kind = "hill", pos = V3(C.X - 125, 0, C.Z + 50), radius = 34, height = 8 },
		{ kind = "hill", pos = V3(C.X + 120, 0, C.Z + 40), radius = 30, height = 7 },
		{ kind = "ridge", pos = V3(C.X, 0, C.Z - 172), radius = 24, height = 20, angle = 0, length = 130 },
		-- flat working areas last, so they override the cone's foot
		{ kind = "flat", pos = SPAWN, radius = 50, target = 0.6, material = Enum.Material.Basalt },
		{ kind = "flat", pos = GATE, radius = 22, target = 0.6, material = Enum.Material.Basalt },
		{ kind = "flat", pos = FLATS, radius = 58, target = 0.6, material = Enum.Material.Basalt },
		{ kind = "flat", pos = TERRACE, radius = 40, target = TERRACE_HEIGHT, material = Enum.Material.Slate },
		{ kind = "flat", pos = CRATER, radius = 24, target = FLOOR_Y, material = Enum.Material.CrackedLava },
	}
end

-- helpers -----------------------------------------------------------------------------------------------------------------------------

local function groundAt(x: number, z: number): number
	return Build.groundY(x, z) or 0.6
end

local function fang(parent: Instance, pos: Vector3, h: number, w: number, lean: number, yaw: number)
	local m = Build.model(parent, "Fang")
	Build.part(m, { name = "FangBody", size = V3(w, h, w), cf = CF(pos + V3(0, h / 2, 0)) * ANG(lean, yaw, 0), color = BASALT, material = Enum.Material.Basalt, shape = "Wedge", collide = true })
	Build.part(m, { name = "FangSeam", size = V3(w * 0.16, h * 0.8, w * 0.4), cf = CF(pos + V3(0, h * 0.42, 0)) * ANG(lean, yaw, 0) * CF(w * 0.3, 0, 0), color = LAVA, neon = true, shape = "Wedge" })
	return m
end

local function embers(part: BasePart, rate: number, speed: number)
	Build.emitter(part, {
		Rate = rate,
		Lifetime = NumberRange.new(1.5, 3),
		Speed = NumberRange.new(speed * 0.5, speed),
		SpreadAngle = Vector2.new(25, 25),
		Color = ColorSequence.new(LAVA_HOT),
		LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
		Acceleration = Vector3.new(0, 6, 0),
		EmissionDirection = Enum.NormalId.Top,
	})
end

-- A glowing pool lying on the ground.
local function lavaPool(parent: Instance, pos: Vector3, radius: number, light: boolean)
	local disc = Build.disc(parent, "LavaPool", V3(pos.X, pos.Y + 0.1, pos.Z), radius * 2, 0.5, { color = LAVA, neon = true })
	Build.disc(parent, "PoolCrust", V3(pos.X, pos.Y + 0.05, pos.Z), radius * 2 + 3, 0.4, { color = IRON, material = Enum.Material.Basalt })
	embers(disc, math.floor(3 + radius), 6)
	if light then
		Build.light(disc, Color3.fromRGB(255, 120, 50), 1.6, 18 + radius * 3)
	end
	return disc
end

-- A river of lava laid down the terrain from `from` along `dir`, ending in a pool.
local function lavaRiver(parent: Instance, from: Vector3, dir: Vector3, maxLength: number, width: number, pool: boolean)
	local pts = Road.flow(from, dir, maxLength, 5)
	for i = 1, #pts - 1 do
		local a, b = pts[i] + V3(0, 0.7, 0), pts[i + 1] + V3(0, 0.7, 0)
		local w = width * (1 - 0.35 * i / #pts)
		Road.strip(parent, "Crust", a - V3(0, 0.15, 0), b - V3(0, 0.15, 0), w + 2, 0.3, IRON, Enum.Material.Basalt)
		Road.strip(parent, "LavaFlow", a, b, w, 0.35, if i % 2 == 0 then LAVA else Color3.fromRGB(255, 130, 50), Enum.Material.Neon)
	end
	if #pts >= 2 then
		local last = pts[#pts]
		if pool then
			lavaPool(parent, last, 6, true)
		end
		local glow = Build.part(parent, { name = "FlowGlow", size = V3(1, 1, 1), cf = CF(pts[math.ceil(#pts / 2)] + V3(0, 3, 0)), transparency = 1 })
		Build.light(glow, Color3.fromRGB(255, 110, 40), 1.4, 36)
	end
end

-- Crater: lava lake, rim falls, the seal's ring of fangs, smoke --------------------------------------------------------------------------------

local function buildCrater(parent: Instance)
	local m = Build.model(parent, "Crater")
	local gy = groundAt(LAKE.X, LAKE.Z)
	lavaPool(m, V3(LAKE.X, gy, LAKE.Z), 9, true)
	for i = 0, 5 do
		local a = (i / 6) * math.pi * 2
		Flora.moltenRock(m, V3(LAKE.X + math.cos(a) * 11.5, groundAt(LAKE.X + math.cos(a) * 11.5, LAKE.Z + math.sin(a) * 11.5), LAKE.Z + math.sin(a) * 11.5), 2.6 + Build.hash(i, 3) * 2, 700 + i)
	end
	-- lava pouring over the rim into the lake
	local towardLake = V3(LAKE.X - CRATER.X, 0, LAKE.Z - CRATER.Z).Unit
	local rim = CRATER + towardLake * (CRATER_RADIUS + 6)
	lavaRiver(m, V3(rim.X, groundAt(rim.X, rim.Z), rim.Z), -towardLake, 30, 4, false)
	-- ring of fangs round the seal's arena
	local sy = groundAt(SEAL.X, SEAL.Z)
	for i = 0, 7 do
		local a = (i / 8) * math.pi * 2 + 0.3
		local x, z = SEAL.X + math.cos(a) * 17, SEAL.Z + math.sin(a) * 17
		if (V3(x, 0, z) - LAKE).Magnitude > 13 then
			fang(m, V3(x, groundAt(x, z) - 1, z), 9 + Build.hash(i, 4) * 6, 3.4, (Build.hash(i, 5) - 0.5) * 0.3, Build.hash(i, 6) * 6)
		end
	end
	Build.sign(m, "THE CALDERA'S MOUTH", CF(SEAL.X - 4, sy + 7, SEAL.Z + 20) * ANG(0, math.pi, 0), V3(18, 2.4, 0.5), Color3.fromRGB(30, 20, 20), Color3.fromRGB(255, 190, 120))
	for _, dx in { -7, 7 } do
		Build.part(m, { name = "MouthPost", size = V3(0.7, 7, 0.7), cf = CF(SEAL.X - 4 + dx, sy + 3.5, SEAL.Z + 20), color = IRON, material = Enum.Material.Metal })
	end
	-- smoke plume, ash fall and a red glow over the whole cone
	local top = Build.part(m, { name = "Plume", size = V3(30, 2, 30), cf = CF(CRATER.X, FLOOR_Y + 8, CRATER.Z), transparency = 1 })
	Build.emitter(top, {
		Rate = 9,
		Lifetime = NumberRange.new(8, 12),
		Speed = NumberRange.new(6, 10),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-25, 25),
		SpreadAngle = Vector2.new(14, 14),
		Color = ColorSequence.new(Color3.fromRGB(58, 52, 56)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 8), NumberSequenceKeypoint.new(1, 26) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }),
		Acceleration = Vector3.new(2, 2, 0),
		EmissionDirection = Enum.NormalId.Top,
	})
	Build.light(top, Color3.fromRGB(255, 110, 50), 2.2, 120)
	local ash = Build.part(m, { name = "AshFall", size = V3(260, 2, 260), cf = CF(CRATER.X, FLOOR_Y + 90, CRATER.Z), transparency = 1 })
	Build.emitter(ash, {
		Rate = 40,
		Lifetime = NumberRange.new(16, 22),
		Speed = NumberRange.new(3, 6),
		SpreadAngle = Vector2.new(25, 25),
		Color = ColorSequence.new(Color3.fromRGB(70, 66, 70)),
		Size = NumberSequence.new(0.5),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.1, 0.2), NumberSequenceKeypoint.new(0.9, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		Acceleration = Vector3.new(1.5, -1, 0.5),
		EmissionDirection = Enum.NormalId.Bottom,
	})
end

-- Flanks: lava rivers, the ember road, gate, fangs ---------------------------------------------------------------------------------------------

local function buildFlanks(parent: Instance): { Vector3 }
	local m = Build.model(parent, "Lava")
	for _, angle in { 0.9, 3.5, 4.6, 5.6 } do
		local dir = V3(math.cos(angle), 0, math.sin(angle))
		local from = CRATER + dir * (CRATER_RADIUS + 4)
		lavaRiver(m, V3(from.X, groundAt(from.X, from.Z), from.Z), dir, 105, 5, true)
	end
	local road = Build.model(parent, "EmberRoad")
	local pts = Road.spiral(road, {
		center = CRATER,
		outer = CONE_RADIUS - 6,
		inner = CRATER_RADIUS + 3,
		turns = 1.5,
		steps = 90,
		theta0 = math.pi / 2,
		colors = { Color3.fromRGB(46, 42, 50), Color3.fromRGB(58, 52, 58) },
		material = Enum.Material.Basalt,
		lampColor = Color3.fromRGB(255, 150, 70),
	})
	local start = pts[1]
	Build.sign(road, "EMBER ROAD  ·  THE CALDERA'S MOUTH", CF(start + V3(-9, 6, 4)) * ANG(0, math.pi, 0), V3(21, 2.4, 0.5), Color3.fromRGB(30, 20, 20), Color3.fromRGB(255, 190, 120))
	Build.part(road, { name = "TrailPostA", size = V3(0.7, 6, 0.7), cf = CF(start + V3(-18, 3, 4)), color = IRON, material = Enum.Material.Metal })
	Build.part(road, { name = "TrailPostB", size = V3(0.7, 6, 0.7), cf = CF(start + V3(0, 3, 4)), color = IRON, material = Enum.Material.Metal })
	return pts
end

local function buildGate(parent: Instance)
	local gate = Build.model(parent, "FangGate")
	local gy = groundAt(GATE.X, GATE.Z)
	local gp = V3(GATE.X, gy, GATE.Z)
	fang(gate, gp + V3(-16, 0, 0), 42, 14, -0.12, 0)
	fang(gate, gp + V3(16, 0, 0), 46, 14, 0.12, math.pi)
	Build.sign(gate, "EMBERFANG VOLCANO", CF(gp + V3(0, 12, 6)) * ANG(0, math.pi, 0), V3(22, 2.6, 0.5), Color3.fromRGB(30, 20, 20), Color3.fromRGB(255, 190, 120))
	for _, dx in { -9, 9 } do
		Build.part(gate, { name = "SignPost", size = V3(0.8, 12, 0.8), cf = CF(gp + V3(dx, 6, 6)), color = IRON, material = Enum.Material.Metal })
	end
	-- the great fang: a towering landmark seen from every island approach
	local fx, fz = C.X + 108, C.Z + 62
	local fy = Build.groundY(fx, fz)
	if fy then
		local big = Build.mesh(gate, "EmberFang", CF(fx, fy + 20, fz), 2.6, true)
		if big then
			big.CFrame = CF(fx, fy + big.Size.Y / 2 - 1, fz)
			local glow = Build.part(gate, { name = "FangGlow", size = V3(1, 1, 1), cf = CF(fx, fy + big.Size.Y * 0.4, fz), transparency = 1 })
			Build.light(glow, ACCENT, 1.6, 70)
		end
	end
end

local function signPost(parent: Instance, text: string, x: number, z: number)
	local gy = groundAt(x, z)
	for _, dx in { -5.5, 5.5 } do
		Build.part(parent, { name = "SignPost", size = V3(0.7, 8, 0.7), cf = CF(x + dx, gy + 4, z), color = IRON, material = Enum.Material.Metal, collide = true })
	end
	Build.sign(parent, text, CF(x, gy + 7, z + 0.2) * ANG(0, math.pi, 0), V3(13, 2.4, 0.5), Color3.fromRGB(30, 20, 20), Color3.fromRGB(255, 190, 120))
end

-- Flora and scatter ---------------------------------------------------------------------------------------------------------------------------------

local function buildScatter(parent: Instance, road: { Vector3 })
	local m = Build.model(parent, "Flora")
	local avoid: { Flora.Zone } = {
		{ pos = SPAWN, radius = 62 },
		{ pos = SKYPORT, radius = 40 },
		{ pos = GATE, radius = 30 },
		{ pos = FLATS, radius = 58 },
		{ pos = TERRACE, radius = 42 },
		{ pos = CRATER, radius = 46 },
	}
	for _, p in road do
		table.insert(avoid, { pos = p, radius = 7 })
	end
	local leaves = { Color3.fromRGB(120, 36, 28), Color3.fromRGB(168, 70, 30), Color3.fromRGB(70, 40, 34) }
	-- scorched trees with a few leaves left, and burnt trunks
	Flora.scatter({
		center = CRATER, radius = 150, count = 38, seed = 3100, minY = 0.3, maxY = 34, avoid = avoid, spacing = 14,
		make = function(pos, i, rnd)
			Flora.broadleaf(m, pos, 9 + rnd * 8, i, { trunk = Color3.fromRGB(34, 28, 28), leaves = leaves })
		end,
	})
	Flora.scatter({
		center = CRATER, radius = 150, count = 50, seed = 3200, minY = 0.3, maxY = 40, avoid = avoid, spacing = 10,
		make = function(pos, i, rnd)
			Flora.charTree(m, pos, 8 + rnd * 8, i)
		end,
	})
	Flora.scatter({
		center = CRATER, radius = 150, count = 45, seed = 3300, minY = 0.3, maxY = 40, avoid = avoid, spacing = 5,
		make = function(pos, i, rnd)
			Flora.bush(m, pos, 2 + rnd * 1.6, i, leaves, if i % 4 == 0 then Color3.fromRGB(255, 150, 60) else nil)
		end,
	})
	Flora.scatter({
		center = CRATER, radius = 150, count = 46, seed = 3400, minY = 0.3, maxY = 60, avoid = avoid, spacing = 9,
		make = function(pos, i, rnd)
			Flora.moltenRock(m, pos, 3 + rnd * 5, i)
		end,
	})
	-- lava pools on the flats, vents and fang spires
	Flora.scatter({
		center = CRATER, radius = 140, count = 7, seed = 3500, minY = 0.2, maxY = 3, avoid = avoid, spacing = 40,
		make = function(pos, i, rnd)
			lavaPool(m, pos, 3.5 + rnd * 3.5, i % 2 == 0)
		end,
	})
	Flora.scatter({
		center = CRATER, radius = 150, count = 16, seed = 3600, minY = 0.2, maxY = 50, avoid = avoid, spacing = 20,
		make = function(pos, i, rnd)
			local vent = Build.pillar(m, "Vent", pos + V3(0, -0.4, 0), 3 + rnd * 2, 1.2, { color = LAVA, neon = true })
			embers(vent, 10, 8)
			if i % 4 == 0 then
				Build.light(vent, Color3.fromRGB(255, 120, 50), 1.2, 22)
			end
		end,
	})
	Flora.scatter({
		center = CRATER, radius = 150, count = 20, seed = 3700, minY = 0.2, maxY = 50, avoid = avoid, spacing = 14,
		make = function(pos, i, rnd)
			fang(m, pos - V3(0, 1, 0), 10 + rnd * 20, 4 + rnd * 5, (rnd - 0.5) * 0.4, rnd * 6)
		end,
	})
end

function Emberfang.build(folder: Folder, ctx: any)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "EmberfangSpawn"
	spawn.Anchored = true
	spawn.Size = V3(12, 1, 12)
	spawn.CFrame = CF(V3(SPAWN.X, 1.1, SPAWN.Z))
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Material = Enum.Material.Basalt
	spawn.Color = Color3.fromRGB(46, 40, 48)
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = folder
	ctx.spawn("Emberfang", spawn)
	Forgeheart.skyport(folder, SKYPORT, "SKYPORT: RETURN", ACCENT, math.rad(200))

	buildGate(folder)
	local road = buildFlanks(folder)
	buildCrater(folder)
	local signs = Build.model(folder, "FieldSigns")
	signPost(signs, "BASALT FLATS", FLATS.X + 6, FLATS.Z + 52)
	signPost(signs, "CINDER TERRACE", TERRACE.X + 6, TERRACE.Z + 34)
	buildScatter(folder, road)
end

return Emberfang
