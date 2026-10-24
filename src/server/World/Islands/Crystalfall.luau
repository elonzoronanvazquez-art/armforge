--!strict
-- FROSTPEAK MOUNTAIN (internal id Crystalfall, biome 3): a huge snow mountain in two stages. A wide cone (walkable, with a spiral road) rises
-- to Base Camp, a plateau ringed by the Crystal Ledge and three mini boss camps; from there a sheer 46-stud crown wall rises to the summit
-- where the Frozen Chorus sleeps. The wall is climbed (three truss routes) or bypassed by the aerial tramway; finishing either grants Summit
-- Momentum (Logic/Momentum, Services/ClimbService, Services/TramService). The builder tags the parts those services read.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local IslandConfig = require(Shared.Config.Islands)
local Creatures = require(Shared.Config.Creatures)
local Mountain = require(Shared.Config.Mountain)
local Build = require(script.Parent.Parent.Build)
local Flora = require(script.Parent.Parent.Flora)
local Road = require(script.Parent.Parent.Road)
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
local MINIS = assert(DEF.miniBosses, "Crystalfall has mini bosses")

local MOUNTAIN = V3(GUARDIAN.position.X, 0, GUARDIAN.position.Z) -- the summit is the centre
local CONE_RADIUS = 120
local CONE_TOP = 70 -- radius of the flat Base Camp plateau
local CONE_HEIGHT = 48
local CROWN_RADIUS = 34
local CROWN_TOP = 33 -- the crown is a near-vertical wall: top radius almost equals its radius
local CROWN_HEIGHT = 46
local PLATEAU_Y = CONE_HEIGHT + 0.6
local SUMMIT_Y = CONE_HEIGHT + CROWN_HEIGHT + 0.6
local SPAWN = V3(C.X, 0, C.Z + 96)
local SKYPORT = V3(C.X + 38, 0, C.Z + 100)
local ARCH = V3(C.X, 0, C.Z + 78)
local MEADOW = DEF.fields[1].center
local LEDGE = DEF.fields[2].center
local BEARING = math.rad(Mountain.Tram.bearing)
local BEARING_DIR = V3(math.cos(BEARING), 0, math.sin(BEARING))
local BASE_STATION = MOUNTAIN + BEARING_DIR * 145
local SUMMIT_STATION = MOUNTAIN + BEARING_DIR * 26
local SUMMIT_DECK = SUMMIT_Y + 8 -- the summit station stands on stilts so cabins clear the crown rim

local SNOW = Color3.fromRGB(240, 246, 252)
local ICE = Color3.fromRGB(176, 218, 240)
local STEEL = Color3.fromRGB(90, 100, 130)
local DARK = Color3.fromRGB(34, 42, 62)
local RED = Color3.fromRGB(190, 70, 60)

function Crystalfall.features(): { IslandTerrain.Feature }
	local feats: { IslandTerrain.Feature } = {
		{ kind = "mound", pos = MOUNTAIN, radius = CONE_RADIUS, height = CONE_HEIGHT, length = CONE_TOP },
		{ kind = "mound", pos = MOUNTAIN, radius = CROWN_RADIUS, height = CROWN_HEIGHT, length = CROWN_TOP },
		{ kind = "hill", pos = V3(C.X + 120, 0, C.Z + 30), radius = 34, height = 9 },
		{ kind = "hill", pos = V3(C.X - 120, 0, C.Z + 90), radius = 30, height = 8 },
		-- flat working areas last, so they override the mountain's flanks and smooth the plateau for the seals
		{ kind = "flat", pos = SPAWN, radius = 30, target = 0.6, material = Enum.Material.Limestone },
		{ kind = "flat", pos = ARCH, radius = 18, target = 0.6, material = Enum.Material.Snow },
		{ kind = "flat", pos = BASE_STATION, radius = 24, target = 0.6, material = Enum.Material.Limestone },
		{ kind = "flat", pos = MEADOW, radius = 56, target = 0.6, material = Enum.Material.Snow },
		{ kind = "flat", pos = LEDGE, radius = 24, target = PLATEAU_Y, material = Enum.Material.Limestone },
		{ kind = "flat", pos = MOUNTAIN, radius = 26, target = SUMMIT_Y, material = Enum.Material.Snow },
	}
	for _, mini in MINIS do
		table.insert(feats, { kind = "flat", pos = mini.position, radius = 17, target = PLATEAU_Y, material = Enum.Material.Snow })
	end
	return feats
end

-- helpers ---------------------------------------------------------------------------------------------------------------------------

local function groundAt(x: number, z: number): number
	return Build.groundY(x, z) or 0.6
end

local function dirAt(deg: number): Vector3
	local a = math.rad(deg)
	return V3(math.cos(a), 0, math.sin(a))
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
				local part = Build.part(arch, {
					name = "ArchCrystal",
					size = V3(4.4 - i * 0.3, h, 4.4 - i * 0.3),
					cf = CF(archPos + V3(side * (13 + i * 0.5), h / 2 - 1, (i - 3.5) * 2.4)) * ANG(0, side * i * 0.3, -side * 0.22),
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

-- Road and Base Camp: the road spirals up the cone to the plateau ------------------------------------------------------------------------------

local function buildRoad(parent: Instance): { Vector3 }
	local m = Build.model(parent, "SummitRoad")
	local pts = Road.spiral(m, {
		center = MOUNTAIN,
		outer = CONE_RADIUS - 6,
		inner = 62,
		turns = 1.92,
		steps = 110,
		theta0 = math.pi / 2,
		colors = { Color3.fromRGB(94, 102, 120), Color3.fromRGB(104, 112, 130) },
		material = Enum.Material.Slate,
		lampColor = Color3.fromRGB(150, 220, 255),
	})
	local start = pts[1]
	Build.sign(m, "BASE CAMP ROAD  ·  CLIMB OR RIDE", CF(start + V3(-9, 6, 4)) * ANG(0, math.pi, 0), V3(21, 2.4, 0.5), DARK, Color3.fromRGB(200, 235, 255))
	Build.part(m, { name = "TrailPostA", size = V3(0.7, 6, 0.7), cf = CF(start + V3(-18, 3, 4)), color = STEEL, material = Enum.Material.Metal })
	Build.part(m, { name = "TrailPostB", size = V3(0.7, 6, 0.7), cf = CF(start + V3(0, 3, 4)), color = STEEL, material = Enum.Material.Metal })
	return pts
end

local function tent(parent: Instance, pos: Vector3, yaw: number, color: Color3)
	local cf = CF(pos) * ANG(0, yaw, 0)
	for _, side in { -1, 1 } do
		Build.part(parent, { name = "TentPanel", size = V3(5, 0.3, 4.4), cf = cf * CF(side * 1.35, 1.7, 0) * ANG(0, 0, -side * 0.9), color = color, material = Enum.Material.Fabric })
	end
	Build.part(parent, { name = "TentBack", size = V3(4.4, 3.4, 0.3), cf = cf * CF(0, 1.7, 2.1), color = color:Lerp(DARK, 0.3), material = Enum.Material.Fabric })
end

local function buildCamp(parent: Instance, at: Vector3)
	local m = Build.model(parent, "BaseCamp")
	local y = groundAt(at.X, at.Z)
	tent(m, V3(at.X + 7, y, at.Z - 4), 0.4, RED)
	tent(m, V3(at.X - 6, y, at.Z - 6), -0.3, Color3.fromRGB(70, 130, 190))
	local fire = Build.part(m, { name = "Bonfire", size = V3(1.6, 1.2, 1.6), cf = CF(at.X, y + 0.8, at.Z + 2), color = Color3.fromRGB(255, 150, 60), neon = true, shape = "Ball" })
	Build.light(fire, Color3.fromRGB(255, 160, 80), 1.6, 32)
	Build.emitter(fire, {
		Rate = 14,
		Lifetime = NumberRange.new(1, 2),
		Speed = NumberRange.new(3, 5),
		SpreadAngle = Vector2.new(14, 14),
		Color = ColorSequence.new(Color3.fromRGB(255, 190, 90)),
		LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
		Acceleration = Vector3.new(0, 4, 0),
		EmissionDirection = Enum.NormalId.Top,
	})
	for k = 0, 3 do
		local a = k * math.pi / 2
		Build.part(m, { name = "Log", size = V3(3, 0.8, 0.8), cf = CF(at.X + math.cos(a) * 2.4, y + 0.5, at.Z + 2 + math.sin(a) * 2.4) * ANG(0, a + 0.6, 0), color = Color3.fromRGB(88, 64, 46), material = Enum.Material.Wood, shape = "Cylinder" })
	end
	Build.sign(m, "BASE CAMP  ·  3 CLIMBING ROUTES  ·  TRAMWAY", CF(at.X, y + 7, at.Z - 10) * ANG(0, math.pi, 0), V3(26, 2.4, 0.5), DARK, Color3.fromRGB(200, 235, 255))
	for _, dx in { -11, 11 } do
		Build.part(m, { name = "CampPost", size = V3(0.7, 7, 0.7), cf = CF(at.X + dx, y + 3.5, at.Z - 10), color = STEEL, material = Enum.Material.Metal })
	end
end

-- Climbing routes: truss lines up the crown wall, with rest ledges, ropes and pitons --------------------------------------------------------------

local function wallRadius(deg: number): number
	local dir = dirAt(deg)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local origin = MOUNTAIN + dir * (CROWN_RADIUS + 14) + V3(0, PLATEAU_Y + 22, 0)
	local hit = workspace:Raycast(origin, -dir * (CROWN_RADIUS + 12), params)
	if hit then
		return (V3(hit.Position.X, 0, hit.Position.Z) - MOUNTAIN).Magnitude
	end
	return CROWN_RADIUS
end

local function buildRoutes(parent: Instance)
	local m = Build.model(parent, "ClimbRoutes")
	for _, route in Mountain.Routes do
		local dir = dirAt(route.angle)
		local wall = wallRadius(route.angle)
		local axis = MOUNTAIN + dir * (wall + 1.2)
		local y0, y1 = PLATEAU_Y, SUMMIT_Y + 3
		local h = y1 - y0
		local facing = CFrame.lookAt(V3(axis.X, 0, axis.Z), V3(MOUNTAIN.X, 0, MOUNTAIN.Z))
		local rot = facing - facing.Position
		-- the climbable truss (native Roblox climbing): tagged so ClimbService can judge the climb
		local truss = Instance.new("TrussPart")
		truss.Name = "Route_" .. route.id
		truss.Anchored = true
		truss.Size = V3(2, h, 2)
		truss.CFrame = CF(axis.X, y0 + h / 2, axis.Z) * rot
		truss.Color = Color3.fromRGB(150, 190, 220)
		truss.Material = Enum.Material.Metal
		truss.Parent = m
		truss:SetAttribute("RouteId", route.id)
		truss:SetAttribute("MinSeconds", route.minSeconds)
		Build.tag(truss, "ClimbRoute")
		-- rest ledges every ~15 studs, jutting out beside the truss
		for k = 1, math.floor(h / 15) do
			Build.part(m, { name = "RestLedge", size = V3(4.4, 0.6, 3), cf = CF(axis.X, y0 + k * 15, axis.Z) * rot * CF(3.4, 0, 0), color = Color3.fromRGB(110, 118, 140), material = Enum.Material.Metal, collide = true })
		end
		-- ropes and pitons on the wall beside the line
		for k = 0, math.floor(h / 6) do
			Build.part(m, { name = "Piton", size = V3(0.5, 0.5, 1.2), cf = CF(axis.X, y0 + 3 + k * 6, axis.Z) * rot * CF(-1.8, 0, 0.6), color = Color3.fromRGB(255, 150, 70), neon = true })
		end
		Build.part(m, { name = "Rope", size = V3(0.3, h, 0.3), cf = CF(axis.X, y0 + h / 2, axis.Z) * rot * CF(1.7, 0, 0), color = Color3.fromRGB(230, 196, 120), material = Enum.Material.Fabric })
		-- a pennant on the rim marks the top, and a sign at the foot names the route
		local top = V3(axis.X, y1 + 1, axis.Z)
		Build.part(m, { name = "FlagPole", size = V3(0.3, 7, 0.3), cf = CF(top + V3(0, 3.5, 0)), color = STEEL, material = Enum.Material.Metal })
		Build.part(m, { name = "Flag", size = V3(3, 1.6, 0.2), cf = CF(top + V3(0, 6.2, 0)) * rot * CF(1.6, 0, 0), color = RED, material = Enum.Material.Fabric })
		local signPos = MOUNTAIN + dir * (wall + 9)
		local signAt = V3(signPos.X, y0 + 6, signPos.Z)
		Build.sign(m, string.upper(route.name) .. "  ·  CLIMB", CFrame.lookAt(signAt, signAt + dir), V3(13, 2.2, 0.5), DARK, Color3.fromRGB(200, 235, 255))
		for _, off in { -5, 5 } do
			local side = dir:Cross(Vector3.yAxis).Unit * off
			Build.part(m, { name = "RoutePost", size = V3(0.6, 6, 0.6), cf = CF(signPos.X + side.X, y0 + 3, signPos.Z + side.Z), color = STEEL, material = Enum.Material.Metal })
		end
	end
end

-- Summit: the seal's arena under pillars of light -------------------------------------------------------------------------------------------------------

local function buildSummit(parent: Instance)
	local m = Build.model(parent, "Summit")
	local gy = groundAt(MOUNTAIN.X, MOUNTAIN.Z)
	Build.disc(m, "IceFloor", V3(MOUNTAIN.X, gy + 0.05, MOUNTAIN.Z), 46, 0.3, { color = ICE, material = Enum.Material.Ice, reflectance = 0.15 })
	Build.disc(m, "RuneRing", V3(MOUNTAIN.X, gy + 0.3, MOUNTAIN.Z), 36, 0.12, { color = Color3.fromRGB(150, 230, 255), neon = true })
	Build.disc(m, "RuneFloor", V3(MOUNTAIN.X, gy + 0.36, MOUNTAIN.Z), 35.2, 0.12, { color = Color3.fromRGB(150, 188, 214), material = Enum.Material.Ice })
	local pal = { Color3.fromRGB(130, 200, 255), Color3.fromRGB(200, 150, 255), Color3.fromRGB(150, 255, 235) }
	for i = 0, 9 do
		local deg = i * 36 + 12
		local off = math.abs(((deg - Mountain.Tram.bearing + 540) % 360) - 180) -- degrees from the tram's bearing
		if off > 28 then
			local d = dirAt(deg) * 17
			local x, z = MOUNTAIN.X + d.X, MOUNTAIN.Z + d.Z
			local y = groundAt(x, z)
			crystalCluster(m, V3(x, y, z), 1.7, 300 + i, pal[1 + i % 3])
			if i % 2 == 0 then
				local beam = Build.pillar(m, "ChoirLight", V3(x, y + 6, z), 3, 90, { color = pal[1 + i % 3], neon = true, transparency = 0.8 })
				Build.light(beam, pal[1 + i % 3], 1.2, 40)
			end
		end
	end
	local signY = groundAt(MOUNTAIN.X, MOUNTAIN.Z - 23)
	Build.sign(m, "THE FROZEN CHORUS", CF(MOUNTAIN.X, signY + 8, MOUNTAIN.Z - 23), V3(18, 2.4, 0.5), DARK, Color3.fromRGB(200, 235, 255))
	for _, dx in { -8, 8 } do
		Build.part(m, { name = "SummitPost", size = V3(0.7, 8, 0.7), cf = CF(MOUNTAIN.X + dx, signY + 4, MOUNTAIN.Z - 23), color = STEEL, material = Enum.Material.Metal })
	end
	-- snowfall over the whole mountain
	local sky = Build.part(m, { name = "Snowfall", size = V3(280, 2, 280), cf = CF(MOUNTAIN.X, gy + 70, MOUNTAIN.Z), transparency = 1 })
	Build.emitter(sky, {
		Rate = 70,
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

-- Mini boss camps -----------------------------------------------------------------------------------------------------------------------------------------

local function buildMiniCamps(parent: Instance)
	local m = Build.model(parent, "MiniBossCamps")
	local pal = { Color3.fromRGB(130, 200, 255), Color3.fromRGB(200, 150, 255), Color3.fromRGB(150, 255, 235) }
	for i, mini in MINIS do
		local def = Creatures.Defs[mini.creature]
		for k = 0, 5 do
			local a = (k / 6) * math.pi * 2 + i
			local x, z = mini.position.X + math.cos(a) * 15, mini.position.Z + math.sin(a) * 15
			crystalCluster(m, V3(x, groundAt(x, z), z), 0.9, 500 + i * 10 + k, pal[1 + (k + i) % 3])
		end
		-- a sign and banner on the camp's outer side
		local out = (V3(mini.position.X, 0, mini.position.Z) - MOUNTAIN).Unit
		local sx, sz = mini.position.X + out.X * 14, mini.position.Z + out.Z * 14
		local sy = groundAt(sx, sz)
		local signAt = V3(sx, sy + 7.5, sz)
		Build.sign(m, string.upper(def.name) .. "  ·  MINI BOSS", CFrame.lookAt(signAt, signAt + out), V3(20, 2.4, 0.5), DARK, Color3.fromRGB(255, 226, 170))
		for _, off in { -8, 8 } do
			local side = out:Cross(Vector3.yAxis).Unit * off
			Build.part(m, { name = "CampPost", size = V3(0.7, 7, 0.7), cf = CF(sx + side.X, sy + 3.5, sz + side.Z), color = STEEL, material = Enum.Material.Metal })
		end
		Build.part(m, { name = "Banner", size = V3(0.2, 5, 3), cf = CFrame.lookAt(V3(sx, sy + 12, sz), V3(sx, sy + 12, sz) + out) * ANG(0, math.pi / 2, 0), color = RED, material = Enum.Material.Fabric })
	end
end

-- Aerial tramway: stations, towers, a double cable and two cabins that TramService moves ---------------------------------------------------------------

local function station(parent: Instance, name: string, label: string, pos: Vector3, deckY: number, stilts: boolean): number
	local m = Build.model(parent, name .. "Station")
	local look = CFrame.lookAt(V3(pos.X, 0, pos.Z), V3(MOUNTAIN.X, 0, MOUNTAIN.Z))
	local face = look - look.Position
	local function at(x: number, y: number, z: number): CFrame
		return CF(pos.X, deckY, pos.Z) * face * CF(x, y, z)
	end
	Build.part(m, { name = "Deck", size = V3(20, 1, 16), cf = at(0, -0.5, 0), color = Color3.fromRGB(70, 80, 104), material = Enum.Material.DiamondPlate, collide = true })
	for _, dx in { -9, 9 } do
		for _, dz in { -7, 7 } do
			Build.part(m, { name = "Pillar", size = V3(1, 13, 1), cf = at(dx, 6.5, dz), color = STEEL, material = Enum.Material.Metal, collide = true })
		end
	end
	Build.part(m, { name = "Roof", size = V3(22, 1, 18), cf = at(0, 13.2, 0), color = Color3.fromRGB(150, 70, 60), material = Enum.Material.Metal })
	Build.part(m, { name = "Wheel", size = V3(1, 9, 9), cf = at(0, 11.4, 0), color = DARK, material = Enum.Material.Metal, shape = "Cylinder" })
	Build.sign(m, label, at(0, 4.4, 8.4) * ANG(0, math.pi, 0), V3(16, 2, 0.4), DARK, Color3.fromRGB(255, 226, 170))
	if stilts then
		for _, dx in { -8, 8 } do
			for _, dz in { -6, 6 } do
				local p = at(dx, 0, dz).Position
				local ground = groundAt(p.X, p.Z)
				Build.part(m, { name = "Stilt", size = V3(1.4, deckY - ground, 1.4), cf = CF(p.X, ground + (deckY - ground) / 2 - 0.5, p.Z), color = STEEL, material = Enum.Material.Metal, collide = true })
			end
		end
		-- stairs down alongside the station, following the rim
		local tangent = (at(1, 0, 0).Position - at(0, 0, 0).Position)
		tangent = V3(tangent.X, 0, tangent.Z).Unit
		local base = at(12, 0, 0).Position
		for k = 0, 11 do
			local p = base + tangent * (k * 1.2)
			local top = deckY - 0.67 * (k + 1)
			Build.part(m, { name = "Stair", size = V3(1.4, 0.5, 5), cf = CFrame.lookAt(V3(p.X, top - 0.25, p.Z), V3(p.X, top - 0.25, p.Z) + tangent) * ANG(0, math.pi / 2, 0), color = Color3.fromRGB(110, 118, 140), material = Enum.Material.Metal, collide = true })
		end
	end
	-- the boarding prompt lives on an invisible part in the middle of the deck; TramService wires it up
	local boarding = Build.part(m, { name = "Boarding", size = V3(6, 1, 6), cf = at(0, 1, 0), transparency = 1 })
	boarding:SetAttribute("Station", name)
	boarding:SetAttribute("Exit", at(0, 0.6, 0).Position)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Ride the tram"
	prompt.ObjectText = "Aerial Tramway"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Mountain.Tram.stationRange
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = boarding
	Build.tag(boarding, "TramStation")
	return deckY + 6.9 -- the cabin pivot (cable point): the cabin floor sits level with the deck
end

local function cabinModel(parent: Instance, index: number, pivot: CFrame, offset: Vector3)
	local m = Build.model(parent, "Cabin" .. index)
	local frame = Build.part(m, { name = "Frame", size = V3(0.4, 0.4, 0.4), cf = pivot, transparency = 1 })
	m.PrimaryPart = frame
	local color = if index == 1 then RED else Color3.fromRGB(70, 130, 190)
	local function at(x: number, y: number, z: number): CFrame
		return pivot * CF(x, y, z)
	end
	Build.part(m, { name = "Hanger", size = V3(0.3, 0.9, 0.3), cf = at(0, -0.45, 0), color = Color3.fromRGB(40, 40, 46), material = Enum.Material.Metal })
	Build.part(m, { name = "Floor", size = V3(4.6, 0.4, 6.4), cf = at(0, -6.9, 0), color = Color3.fromRGB(70, 74, 88), material = Enum.Material.DiamondPlate })
	Build.part(m, { name = "CabinBack", size = V3(4.6, 5.6, 0.3), cf = at(0, -4.1, -3.1), color = color, material = Enum.Material.Metal })
	Build.part(m, { name = "CabinFront", size = V3(4.6, 5.6, 0.3), cf = at(0, -4.1, 3.1), color = color, material = Enum.Material.Metal })
	for _, dx in { -2.2, 2.2 } do
		Build.part(m, { name = "CabinSide", size = V3(0.3, 1.4, 6.4), cf = at(dx, -6.1, 0), color = color, material = Enum.Material.Metal })
		Build.part(m, { name = "CabinWindow", size = V3(0.2, 3.4, 6), cf = at(dx, -3.7, 0), color = Color3.fromRGB(190, 230, 255), neon = true, transparency = 0.6 })
		Build.part(m, { name = "CabinPost", size = V3(0.35, 5.6, 0.35), cf = at(dx, -4.1, 3), color = color, material = Enum.Material.Metal })
		Build.part(m, { name = "CabinPost", size = V3(0.35, 5.6, 0.35), cf = at(dx, -4.1, -3), color = color, material = Enum.Material.Metal })
	end
	Build.part(m, { name = "CabinRoof", size = V3(5, 0.4, 6.8), cf = at(0, -0.9, 0), color = Color3.fromRGB(240, 240, 244), material = Enum.Material.Metal })
	local lamp = Build.part(m, { name = "CabinLamp", size = V3(0.8, 0.8, 0.8), cf = at(0, -1.5, 0), color = Color3.fromRGB(255, 226, 170), neon = true, shape = "Ball" })
	Build.light(lamp, Color3.fromRGB(255, 226, 170), 0.8, 14)
	m:SetAttribute("Cabin", index)
	m:SetAttribute("Offset", offset)
	Build.tag(m, "TramCabin")
end

local function buildTramway(parent: Instance)
	local m = Build.model(parent, "Tramway")
	local baseGround = groundAt(BASE_STATION.X, BASE_STATION.Z)
	local pivotA = station(m, "base", "TRAMWAY  ·  UP TO THE SUMMIT", BASE_STATION, baseGround + 0.8, false)
	local pivotB = station(m, "summit", "SUMMIT STATION  ·  DOWN TO BASE CAMP", SUMMIT_STATION, SUMMIT_DECK, true)
	local a = V3(BASE_STATION.X, pivotA, BASE_STATION.Z)
	local b = V3(SUMMIT_STATION.X, pivotB, SUMMIT_STATION.Z)
	local across = (b - a).Unit:Cross(Vector3.yAxis).Unit * 3.4
	for _, off in { across, -across } do
		Road.strip(m, "Cable", a + off + V3(0, 0.1, 0), b + off + V3(0, 0.1, 0), 0.3, 0.3, Color3.fromRGB(40, 40, 46), Enum.Material.Metal)
	end
	m:SetAttribute("CableA", a)
	m:SetAttribute("CableB", b)
	Build.tag(m, "Tramway")
	-- two towers holding the cable
	for _, f in { 0.34, 0.66 } do
		local p = a:Lerp(b, f)
		local gy = groundAt(p.X, p.Z)
		local top = p.Y + 1.2
		Build.pillar(m, "TowerLeg", V3(p.X, gy - 2, p.Z), 1.6, top - gy + 2, { color = STEEL, material = Enum.Material.Metal, collide = true })
		Build.part(m, { name = "TowerArm", size = V3(10, 0.7, 0.7), cf = CFrame.lookAt(V3(p.X, top, p.Z), V3(p.X, top, p.Z) + across.Unit) * ANG(0, math.pi / 2, 0), color = STEEL, material = Enum.Material.Metal })
	end
	-- the cabins start at their stations; TramService pivots them along the cable from here
	local dir = b - a
	local face = CFrame.lookAt(Vector3.zero, V3(dir.X, 0, dir.Z))
	cabinModel(m, 1, CF(a + across) * face, across)
	cabinModel(m, 2, CF(b - across) * face, -across)
end

-- Flora ---------------------------------------------------------------------------------------------------------------------------------------------------------

local function buildFlora(parent: Instance, road: { Vector3 })
	local m = Build.model(parent, "Flora")
	local avoid: { Flora.Zone } = {
		{ pos = SPAWN, radius = 62 },
		{ pos = SKYPORT, radius = 40 },
		{ pos = ARCH, radius = 32 },
		{ pos = MEADOW, radius = 56 },
		{ pos = LEDGE, radius = 30 },
		{ pos = BASE_STATION, radius = 34 },
		{ pos = MOUNTAIN, radius = 40 },
	}
	for _, mini in MINIS do
		table.insert(avoid, { pos = mini.position, radius = 24 })
	end
	for _, p in road do
		table.insert(avoid, { pos = p, radius = 7 })
	end
	-- pines on the cone, thinning out toward Base Camp
	Flora.scatter({
		center = MOUNTAIN, radius = 160, count = 150, seed = 2100, minY = 0.3, maxY = 44, avoid = avoid, spacing = 8,
		make = function(pos, i, rnd)
			Flora.pine(m, pos, 10 + rnd * 12, i, pos.Y > 5)
		end,
	})
	Flora.scatter({
		center = MOUNTAIN, radius = 160, count = 70, seed = 2200, minY = 0.3, maxY = 50, avoid = avoid, spacing = 5,
		make = function(pos, i, rnd)
			Flora.bush(m, pos, 2 + rnd * 1.6, i, { Color3.fromRGB(196, 222, 214), Color3.fromRGB(170, 204, 196), Color3.fromRGB(226, 238, 236) }, nil)
		end,
	})
	-- snow-capped rocks all the way up (below the summit arena)
	Flora.scatter({
		center = MOUNTAIN, radius = 150, count = 70, seed = 2300, minY = 0.3, maxY = SUMMIT_Y + 1, avoid = avoid, spacing = 9,
		make = function(pos, i, rnd)
			Flora.mossRock(m, pos, 3 + rnd * 5, i, Color3.fromRGB(116, 124, 142), SNOW, Enum.Material.Snow)
		end,
	})
	Flora.scatter({
		center = MOUNTAIN, radius = 150, count = 14, seed = 2400, minY = 0.3, maxY = 60, avoid = avoid, spacing = 22,
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
			cf = CF(MOUNTAIN.X + math.cos(a) * r, 60 + Build.hash(i, 7) * 60, MOUNTAIN.Z + math.sin(a) * r) * ANG(Build.hash(i, 8), Build.hash(i, 9) * 6, 0.4),
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
	local last = road[#road]
	local inward = (V3(MOUNTAIN.X, 0, MOUNTAIN.Z) - V3(last.X, 0, last.Z)).Unit
	buildCamp(folder, last + inward * 8)
	buildRoutes(folder)
	buildSummit(folder)
	buildMiniCamps(folder)
	buildTramway(folder)
	local signs = Build.model(folder, "FieldSigns")
	signPost(signs, "SNOWDRIFT MEADOW", MEADOW.X + 6, MEADOW.Z + 52)
	signPost(signs, "CRYSTAL LEDGE", LEDGE.X + 14, LEDGE.Z + 22)
	buildFlora(folder, road)
end

return Crystalfall
