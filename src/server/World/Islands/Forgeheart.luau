--!strict
-- FORGEHEART ISLE: the starting island. Plaza and spawn, the Great Forge landmark, the Starter Field and Deep Quarry,
-- the Training Yard (four stations), the Armory (arm gallery), the Reforge Core (rebirth) and the Skyport (islands).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local Arms = require(Shared.Config.Arms)
local Assets = require(Shared.Config.Assets)
local ArmBuilder = require(Shared.Runtime.ArmBuilder)
local Build = require(script.Parent.Parent.Build)
local IslandTerrain = require(script.Parent.Parent.IslandTerrain)

local Forgeheart = {}

local IRON = Color3.fromRGB(52, 50, 58)
local STEEL = Color3.fromRGB(122, 126, 136)
local COPPER = Color3.fromRGB(196, 112, 60)
local GLOW = Color3.fromRGB(255, 150, 60)
local BRASS = Color3.fromRGB(214, 170, 80)
local CREAM = Color3.fromRGB(255, 236, 200)
local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles

local PLAZA = V3(0, 0, 20)
local FORGE = V3(0, 0, -22)
local TRAIN = V3(-124, 0, 8)
local ARMORY = V3(122, 0, 6)
local ALTAR = V3(-98, 0, -78)
local SKYPORT = V3(112, 0, 112)

function Forgeheart.features(): { IslandTerrain.Feature }
	return {
		{ kind = "flat", pos = PLAZA, radius = 66, target = 0.6, material = Enum.Material.Pavement },
		{ kind = "flat", pos = FORGE, radius = 44, target = 0.6, material = Enum.Material.Concrete },
		{ kind = "flat", pos = TRAIN, radius = 52, target = 0.6, material = Enum.Material.Concrete },
		{ kind = "flat", pos = ARMORY, radius = 48, target = 0.6, material = Enum.Material.Pavement },
		{ kind = "flat", pos = ALTAR, radius = 30, target = 0.6, material = Enum.Material.Basalt },
		{ kind = "flat", pos = SKYPORT, radius = 46, target = 0.6, material = Enum.Material.Pavement },
		{ kind = "flat", pos = V3(-6, 0, -118), radius = 60, target = 0.6, material = Enum.Material.Ground },
		{ kind = "flat", pos = V3(128, 0, -138), radius = 54, target = 0.6, material = Enum.Material.Slate },
		-- ridges that wall the island in and frame the views
		{ kind = "ridge", pos = V3(-10, 0, -228), radius = 26, height = 22, angle = 0, length = 190 },
		{ kind = "ridge", pos = V3(-196, 0, -80), radius = 22, height = 18, angle = math.pi / 2, length = 150 },
		{ kind = "ridge", pos = V3(204, 0, -70), radius = 22, height = 16, angle = math.pi / 2, length = 150 },
		{ kind = "hill", pos = V3(60, 0, -80), radius = 30, height = 7 },
		{ kind = "hill", pos = V3(-70, 0, 120), radius = 34, height = 6 },
		{ kind = "hill", pos = V3(170, 0, 60), radius = 26, height = 8 },
	}
end

-- helpers --------------------------------------------------------------------------------------------------------

local function ringLine(parent: Instance, center: Vector3, radius: number, count: number, width: number, color: Color3, y: number)
	local m = Build.model(parent, "RingLine")
	for i = 0, count - 1 do
		local a = (i / count) * math.pi * 2
		local pos = center + V3(math.cos(a) * radius, y, math.sin(a) * radius)
		local len = (2 * math.pi * radius / count) * 0.85
		Build.part(m, { name = "Seg", size = V3(len, 0.12, width), cf = CF(pos) * ANG(0, -a + math.pi / 2, 0), color = color, neon = true })
	end
end

local function lamp(parent: Instance, pos: Vector3, height: number, withLight: boolean)
	Build.pillar(parent, "LampPost", pos, 0.7, height, { color = IRON, material = Enum.Material.Metal, collide = true })
	local head = Build.part(parent, { name = "LampHead", size = V3(1.6, 1.1, 1.6), cf = CF(pos + V3(0, height + 0.3, 0)), color = GLOW, neon = true })
	Build.part(parent, { name = "LampCap", size = V3(2.2, 0.3, 2.2), cf = CF(pos + V3(0, height + 1, 0)), color = IRON })
	if withLight then
		Build.light(head, GLOW, 1.4, 24)
	end
end

local function crate(parent: Instance, pos: Vector3, size: number, yaw: number)
	Build.part(parent, { name = "Crate", size = V3(size, size, size), cf = CF(pos + V3(0, size / 2, 0)) * ANG(0, yaw, 0), color = Color3.fromRGB(130, 96, 64), material = Enum.Material.WoodPlanks, collide = true })
	Build.part(parent, { name = "CrateBand", size = V3(size * 1.04, size * 0.16, size * 1.04), cf = CF(pos + V3(0, size / 2, 0)) * ANG(0, yaw, 0), color = IRON, material = Enum.Material.Metal })
end

-- Great Forge ---------------------------------------------------------------------------------------------------------

local function buildForge(parent: Instance)
	local m = Build.model(parent, "GreatForge")
	local y0 = 0.6
	-- plinth with steps toward the plaza
	Build.part(m, { name = "Plinth", size = V3(54, 4, 44), cf = CF(FORGE + V3(0, y0 + 2, 0)), color = Color3.fromRGB(72, 68, 74), material = Enum.Material.Concrete, collide = true })
	Build.part(m, { name = "Step1", size = V3(30, 1.2, 4), cf = CF(FORGE + V3(0, y0 + 0.6, 24)), color = Color3.fromRGB(86, 80, 84), material = Enum.Material.Concrete, collide = true })
	Build.part(m, { name = "Step2", size = V3(26, 1.2, 3), cf = CF(FORGE + V3(0, y0 + 1.8, 21.2)), color = Color3.fromRGB(94, 88, 92), material = Enum.Material.Concrete, collide = true })
	local top = y0 + 4

	-- furnace hall
	Build.part(m, { name = "Hall", size = V3(34, 20, 22), cf = CF(FORGE + V3(0, top + 10, -6)), color = IRON, material = Enum.Material.Metal, collide = true })
	Build.part(m, { name = "HallPlate", size = V3(35, 2.4, 23), cf = CF(FORGE + V3(0, top + 20.6, -6)), color = Color3.fromRGB(70, 66, 76), material = Enum.Material.DiamondPlate, collide = true })
	for i = -1, 1 do
		Build.part(m, { name = "Rib", size = V3(1.6, 20, 23.4), cf = CF(FORGE + V3(i * 13, top + 10, -6)), color = STEEL, material = Enum.Material.Metal })
	end
	-- the furnace mouth
	Build.part(m, { name = "MouthFrame", size = V3(16, 11, 1.6), cf = CF(FORGE + V3(0, top + 6.5, 5.3)), color = COPPER, material = Enum.Material.Metal })
	local mouth = Build.part(m, { name = "Mouth", size = V3(13, 8.6, 0.8), cf = CF(FORGE + V3(0, top + 6.5, 5.9)), color = GLOW, neon = true })
	Build.light(mouth, GLOW, 2.2, 42)
	Build.emitter(mouth, {
		Rate = 14,
		Lifetime = NumberRange.new(1.5, 2.8),
		Speed = NumberRange.new(2, 5),
		SpreadAngle = Vector2.new(25, 25),
		Color = ColorSequence.new(Color3.fromRGB(255, 190, 90)),
		LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		Acceleration = Vector3.new(0, 3, 0),
		EmissionDirection = Enum.NormalId.Front,
	})
	-- title sign
	Build.sign(m, "ARMFORGE", CF(FORGE + V3(0, top + 17.2, 5.5)), V3(26, 4.4, 0.8), Color3.fromRGB(32, 30, 36), CREAM)
	-- chimneys
	for _, dx in { -11, 11 } do
		local chim = Build.pillar(m, "Chimney", FORGE + V3(dx, top + 20, -12), 6.4, 34, { color = Color3.fromRGB(74, 70, 78), material = Enum.Material.Brick, collide = true })
		local ring = Build.pillar(m, "ChimneyRing", FORGE + V3(dx, top + 52, -12), 7.4, 1.2, { color = GLOW, neon = true })
		Build.emitter(chim, {
			Rate = 8,
			Lifetime = NumberRange.new(5, 8),
			Speed = NumberRange.new(4, 7),
			Color = ColorSequence.new(Color3.fromRGB(70, 64, 70)),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 14) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }),
			Acceleration = Vector3.new(1.5, 1, 0),
		})
		ring.Name = "ChimneyGlow"
	end
	-- anvil in front
	local ax = FORGE + V3(0, top, 14)
	Build.part(m, { name = "AnvilBase", size = V3(5, 2.4, 3.4), cf = CF(ax + V3(0, 1.2, 0)), color = IRON, material = Enum.Material.Metal, collide = true })
	Build.part(m, { name = "AnvilWaist", size = V3(3, 1.4, 2.4), cf = CF(ax + V3(0, 3.1, 0)), color = Color3.fromRGB(70, 70, 80), material = Enum.Material.Metal, collide = true })
	Build.part(m, { name = "AnvilFace", size = V3(8, 1.4, 3.2), cf = CF(ax + V3(0, 4.5, 0)), color = STEEL, material = Enum.Material.Metal, collide = true })
	Build.part(m, { name = "AnvilHorn", size = V3(3.2, 1.4, 3.2), cf = CF(ax + V3(5.6, 4.5, 0)) * ANG(0, math.pi / 2, 0), color = STEEL, material = Enum.Material.Metal, shape = "Wedge" })
	Build.part(m, { name = "HotBar", size = V3(5, 0.5, 0.8), cf = CF(ax + V3(0, 5.45, 0)), color = Color3.fromRGB(255, 120, 40), neon = true })
	-- hanging crane
	Build.part(m, { name = "CranePost", size = V3(1.6, 24, 1.6), cf = CF(FORGE + V3(-24, top + 12, 4)), color = STEEL, material = Enum.Material.Metal, collide = true })
	Build.part(m, { name = "CraneArm", size = V3(20, 1.4, 1.4), cf = CF(FORGE + V3(-14, top + 24, 4)), color = STEEL, material = Enum.Material.Metal })
	Build.part(m, { name = "CraneCable", size = V3(0.3, 12, 0.3), cf = CF(FORGE + V3(-6, top + 17.6, 4)), color = Color3.fromRGB(30, 30, 30) })
	Build.part(m, { name = "CraneHook", size = V3(2, 2, 2), cf = CF(FORGE + V3(-6, top + 11, 4)), color = GLOW, neon = true, shape = "Ball" })
	-- pipes with glowing bands
	for _, dx in { -17.6, 17.6 } do
		Build.pillar(m, "Pipe", FORGE + V3(dx, top, 4), 2, 17, { color = COPPER, material = Enum.Material.Metal, collide = true })
		for k = 1, 3 do
			Build.pillar(m, "PipeBand", FORGE + V3(dx, top + k * 4.5, 4), 2.3, 0.5, { color = GLOW, neon = true })
		end
	end
	-- optional AI hero mesh (kept as a decorative crown if it generated)
	local hero = Assets.Meshes.ForgeHero
	if hero then
		local ok, mesh = pcall(function()
			return game:GetService("AssetService"):CreateMeshPartAsync(hero.mesh :: any)
		end)
		if ok and mesh then
			mesh.Anchored = true
			mesh.CanCollide = false
			mesh.Size = hero.size
			if hero.texture then
				mesh.TextureID = hero.texture :: any
			end
			mesh.CFrame = CF(FORGE + V3(0, top + 36, -30))
			mesh.Name = "ForgeHeroMesh"
			mesh.Parent = m
		end
	end
	return m
end

-- Halo gate: a huge slowly spinning ring above the forge ------------------------------------------------------------------

local function buildHalo(parent: Instance)
	local m = Build.model(parent, "Halo")
	local center = V3(0, 118, -92)
	local segments = 44
	local radius = 74
	for i = 0, segments - 1 do
		local a = (i / segments) * math.pi * 2
		local pos = center + V3(math.cos(a) * radius, math.sin(a) * radius, 0)
		local rot = ANG(0, 0, a + math.pi / 2)
		Build.part(m, { name = "Seg", size = V3(10, 4, 5), cf = CF(pos) * rot, color = Color3.fromRGB(70, 66, 78), material = Enum.Material.Metal })
		Build.part(m, { name = "Glow", size = V3(9.4, 0.8, 5.4), cf = CF(pos) * rot * CF(0, 2.1, 0), color = if i % 4 == 0 then GLOW else Color3.fromRGB(255, 190, 120), neon = true })
		if i % 11 == 0 then
			Build.part(m, { name = "Spoke", size = V3(2, radius * 0.5, 2), cf = CF(center + V3(math.cos(a) * radius * 0.5, math.sin(a) * radius * 0.5, 0)) * ANG(0, 0, a - math.pi / 2), color = Color3.fromRGB(58, 54, 64), material = Enum.Material.Metal })
		end
	end
	local core = Build.part(m, { name = "Core", size = V3(14, 14, 14), cf = CF(center), color = GLOW, neon = true, shape = "Ball" })
	Build.light(core, GLOW, 1.6, 70)
	m:SetAttribute("SpinSpeed", 0.05)
	m:SetAttribute("SpinCenter", center)
	Build.tag(m, "Spin")
	m.PrimaryPart = core
end

-- Plaza, spawn and guide path ----------------------------------------------------------------------------------------

local function buildPlaza(parent: Instance, ctx: any)
	local m = Build.model(parent, "Plaza")
	ringLine(m, PLAZA, 20, 40, 0.7, GLOW, 0.65)
	ringLine(m, PLAZA, 38, 64, 0.5, Color3.fromRGB(255, 196, 140), 0.65)
	ringLine(m, PLAZA, 56, 90, 0.4, Color3.fromRGB(200, 150, 110), 0.65)
	-- central emblem
	Build.disc(m, "Emblem", PLAZA + V3(0, 0.55, 0), 14, 0.2, { color = Color3.fromRGB(40, 38, 46), material = Enum.Material.Metal })
	Build.disc(m, "EmblemGlow", PLAZA + V3(0, 0.7, 0), 10, 0.15, { color = GLOW, neon = true })
	-- spawn pad
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "ForgeheartSpawn"
	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.Size = V3(14, 1, 14)
	spawn.CFrame = CF(V3(0, 1.1, 78))
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Material = Enum.Material.Metal
	spawn.Color = Color3.fromRGB(48, 46, 54)
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = m
	Build.disc(m, "SpawnRing", V3(0, 1.6, 78), 12, 0.15, { color = GLOW, neon = true })
	ctx.spawn("Forgeheart", spawn)
	-- lamps around the plaza (8 lit posts)
	for _, p in Build.ringPoints(PLAZA, 46, 8, 0.2) do
		lamp(m, V3(p.X, 0.6, p.Z), 11, true)
	end
	-- guide path from the spawn to the Starter Field: glowing dashes
	local route = { V3(0, 0, 66), V3(0, 0, 40), V3(-34, 0, 40), V3(-34, 0, -52), V3(-12, 0, -64) }
	local guide = Build.model(m, "GuidePath")
	for i = 1, #route - 1 do
		local a, b = route[i], route[i + 1]
		local dist = (b - a).Magnitude
		local dir = (b - a).Unit
		for d = 4, dist - 2, 6 do
			local pos = a + dir * d
			Build.part(guide, { name = "Dash", size = V3(1.1, 0.12, 3.2), cf = CF(V3(pos.X, 0.68, pos.Z), V3(pos.X, 0.68, pos.Z) + dir), color = Color3.fromRGB(255, 210, 150), neon = true })
		end
	end
	Build.sign(m, "START HERE  >", CF(V3(-24, 5, 36)) * ANG(0, math.rad(35), 0), V3(14, 3, 0.6), Color3.fromRGB(34, 32, 38), CREAM)
	Build.part(m, { name = "SignPost", size = V3(0.8, 5, 0.8), cf = CF(V3(-24, 2.6, 36)), color = IRON, material = Enum.Material.Metal })
end

-- Starter Field & Quarry dressing ------------------------------------------------------------------------------------

local function buildFields(parent: Instance)
	local m = Build.model(parent, "Fields")
	-- starter field arch
	local archPos = V3(-6, 0, -66)
	Build.part(m, { name = "ArchL", size = V3(2.4, 14, 2.4), cf = CF(archPos + V3(-12, 7.6, 0)), color = IRON, material = Enum.Material.Metal, collide = true })
	Build.part(m, { name = "ArchR", size = V3(2.4, 14, 2.4), cf = CF(archPos + V3(12, 7.6, 0)), color = IRON, material = Enum.Material.Metal, collide = true })
	Build.part(m, { name = "ArchTop", size = V3(30, 2.4, 2.8), cf = CF(archPos + V3(0, 14.6, 0)), color = COPPER, material = Enum.Material.Metal })
	Build.sign(m, "THE STARTER FIELD", CF(archPos + V3(0, 14.6, 1.5)), V3(24, 2, 0.4), Color3.fromRGB(34, 32, 38), CREAM)
	Build.part(m, { name = "ArchGlowL", size = V3(0.6, 12, 0.6), cf = CF(archPos + V3(-12, 7.6, 1.3)), color = GLOW, neon = true })
	Build.part(m, { name = "ArchGlowR", size = V3(0.6, 12, 0.6), cf = CF(archPos + V3(12, 7.6, 1.3)), color = GLOW, neon = true })
	-- crates, lanterns and cart rails round the fields
	for i = 1, 14 do
		local a = Build.hash(i, 3) * math.pi * 2
		local r = 40 + Build.hash(i, 9) * 26
		local x, z = -6 + math.cos(a) * r, -118 + math.sin(a) * r
		local y = Build.groundY(x, z)
		if y and math.abs(y - 0.6) < 1.6 then
			if i % 3 == 0 then
				crate(m, V3(x, y, z), 2 + Build.hash(i, 5) * 1.6, Build.hash(i, 7) * 3)
			elseif i % 3 == 1 then
				lamp(m, V3(x, y, z), 6, false)
			end
		end
	end
	local qSign = V3(128, 0, -88)
	Build.sign(m, "DEEP QUARRY", CF(qSign + V3(0, 9, 0)), V3(18, 2.4, 0.5), Color3.fromRGB(34, 32, 38), CREAM)
	Build.part(m, { name = "QSignL", size = V3(1.2, 9, 1.2), cf = CF(qSign + V3(-9, 4.6, 0)), color = IRON, material = Enum.Material.Metal, collide = true })
	Build.part(m, { name = "QSignR", size = V3(1.2, 9, 1.2), cf = CF(qSign + V3(9, 4.6, 0)), color = IRON, material = Enum.Material.Metal, collide = true })
end

-- Training yard --------------------------------------------------------------------------------------------------------------

local function stationBase(parent: Instance, id: string, name: string, pos: Vector3, facing: number, color: Color3): BasePart
	local m = Build.model(parent, name)
	local cf = CF(pos) * ANG(0, facing, 0)
	Build.disc(m, "Floor", pos + V3(0, 0.55, 0), 15, 0.5, { color = Color3.fromRGB(58, 56, 64), material = Enum.Material.DiamondPlate, collide = true })
	Build.disc(m, "FloorGlow", pos + V3(0, 1.1, 0), 13.4, 0.1, { color = color, neon = true })
	Build.disc(m, "FloorInner", pos + V3(0, 1.15, 0), 12.4, 0.1, { color = Color3.fromRGB(44, 42, 50), material = Enum.Material.Metal })
	local stand = Build.part(m, { name = "Station", size = V3(5, 1, 5), cf = cf * CF(0, 1.9, 4), transparency = 1 })
	stand:SetAttribute("StationId", id)
	Build.tag(stand, "TrainStation")
	local prompt = Build.prompt(stand, "Train", name, "Training", 0, 16)
	prompt:SetAttribute("StationId", id)
	return stand
end

local function buildTraining(parent: Instance)
	local m = Build.model(parent, "TrainingYard")
	Build.sign(m, "TRAINING YARD", CF(TRAIN + V3(18, 9, 38)) * ANG(0, math.rad(-150), 0), V3(18, 3, 0.6), Color3.fromRGB(34, 32, 38), CREAM)
	Build.part(m, { name = "SignPost", size = V3(1, 9, 1), cf = CF(TRAIN + V3(18, 4.6, 38)), color = IRON, material = Enum.Material.Metal, collide = true })
	-- four stations on an arc facing the yard centre
	local specs = {
		{ id = "Power", name = "Power Press", angle = 215, color = Color3.fromRGB(255, 120, 70) },
		{ id = "Haste", name = "Speed Bag", angle = 255, color = Color3.fromRGB(255, 210, 80) },
		{ id = "Precision", name = "Target Range", angle = 295, color = Color3.fromRGB(110, 230, 255) },
		{ id = "Endurance", name = "Endurance Rig", angle = 335, color = Color3.fromRGB(150, 255, 150) },
	}
	for _, spec in specs do
		local a = math.rad(spec.angle)
		local pos = TRAIN + V3(math.cos(a) * 30, 0, math.sin(a) * 30)
		local facing = -a + math.pi / 2 + math.pi
		stationBase(m, spec.id, spec.name, pos, facing, spec.color)
		local cf = CF(pos) * ANG(0, facing, 0)
		local color: Color3 = spec.color
		if spec.id == "Power" then
			-- hydraulic press: two posts, a beam and a heavy platen
			for _, dx in { -4, 4 } do
				Build.part(m, { name = "PressPost", size = V3(1.4, 14, 1.4), cf = cf * CF(dx, 8, -2), color = STEEL, material = Enum.Material.Metal, collide = true })
			end
			Build.part(m, { name = "PressBeam", size = V3(10.6, 2, 2.4), cf = cf * CF(0, 15.4, -2), color = IRON, material = Enum.Material.Metal })
			Build.pillar(m, "PressRam", (cf * CF(0, 7.6, -2)).Position, 1.4, 7, { color = Color3.fromRGB(200, 205, 215), material = Enum.Material.Metal })
			Build.part(m, { name = "PressPlaten", size = V3(7, 1.6, 4), cf = cf * CF(0, 7.4, -2), color = IRON, material = Enum.Material.DiamondPlate })
			Build.part(m, { name = "PressAnvil", size = V3(7, 2, 4), cf = cf * CF(0, 2, -2), color = Color3.fromRGB(70, 70, 82), material = Enum.Material.Metal, collide = true })
			Build.part(m, { name = "PressZone", size = V3(0.4, 8, 0.6), cf = cf * CF(4.9, 8, -2), color = color, neon = true })
		elseif spec.id == "Haste" then
			Build.part(m, { name = "BagPostL", size = V3(1, 14, 1), cf = cf * CF(-5, 8, -3), color = STEEL, material = Enum.Material.Metal, collide = true })
			Build.part(m, { name = "BagPostR", size = V3(1, 14, 1), cf = cf * CF(5, 8, -3), color = STEEL, material = Enum.Material.Metal, collide = true })
			Build.part(m, { name = "BagBeam", size = V3(11, 1.2, 1.2), cf = cf * CF(0, 14.8, -3), color = IRON, material = Enum.Material.Metal })
			Build.pillar(m, "BagChain", (cf * CF(0, 9.6, -3)).Position, 0.25, 5, { color = Color3.fromRGB(30, 30, 30) })
			Build.pillar(m, "Bag", (cf * CF(0, 5.2, -3)).Position, 2.6, 4.6, { color = Color3.fromRGB(150, 70, 46), material = Enum.Material.Leather })
			Build.part(m, { name = "BagStrap", size = V3(0.3, 2.8, 2.8), cf = cf * CF(0, 6.4, -3) * ANG(0, 0, math.pi / 2), color = BRASS, material = Enum.Material.Metal, shape = "Cylinder" })
		elseif spec.id == "Precision" then
			Build.part(m, { name = "RangeWall", size = V3(16, 11, 1.2), cf = cf * CF(0, 6.4, -8), color = Color3.fromRGB(46, 44, 54), material = Enum.Material.Metal, collide = true })
			for i, dx in { -5, 0, 5 } do
				local ty = if i == 2 then 7.6 else 6.4
				Build.part(m, { name = "TargetRing", size = V3(0.5, 4.4, 4.4), cf = cf * CF(dx, ty, -7.3) * ANG(0, math.pi / 2, 0), color = Color3.fromRGB(240, 240, 240), material = Enum.Material.Metal, shape = "Cylinder" })
				Build.part(m, { name = "TargetMid", size = V3(0.56, 3, 3), cf = cf * CF(dx, ty, -7.25) * ANG(0, math.pi / 2, 0), color = Color3.fromRGB(220, 60, 50), material = Enum.Material.Metal, shape = "Cylinder" })
				Build.part(m, { name = "TargetEye", size = V3(0.6, 1.2, 1.2), cf = cf * CF(dx, ty, -7.2) * ANG(0, math.pi / 2, 0), color = color, neon = true, shape = "Cylinder" })
			end
		else
			Build.pillar(m, "RigPylon", (cf * CF(0, 1.2, -2)).Position, 2.4, 12, { color = IRON, material = Enum.Material.Metal, collide = true })
			for k = 1, 4 do
				Build.pillar(m, "RigRing", (cf * CF(0, 1.2 + k * 2.6, -2)).Position, 3.6, 0.5, { color = color, neon = true })
			end
			for _, dx in { -4, 4 } do
				Build.part(m, { name = "RigHandle", size = V3(0.8, 0.8, 4), cf = cf * CF(dx, 5, 0), color = STEEL, material = Enum.Material.Metal })
			end
		end
	end
	lamp(m, TRAIN + V3(0, 0.6, 0), 12, true)
end

-- Armory -------------------------------------------------------------------------------------------------------------------

local function buildArmory(parent: Instance)
	local m = Build.model(parent, "Armory")
	-- long back wall with a sign, six pedestals in a shallow arc
	local wallCF = CF(ARMORY + V3(0, 0, 18))
	Build.part(m, { name = "BackWall", size = V3(60, 18, 2), cf = wallCF * CF(0, 9.6, 0), color = Color3.fromRGB(46, 44, 54), material = Enum.Material.Metal, collide = true })
	Build.part(m, { name = "WallTrim", size = V3(60.6, 1.2, 2.6), cf = wallCF * CF(0, 18.6, 0), color = COPPER, material = Enum.Material.Metal })
	Build.sign(m, "THE ARMORY", wallCF * CF(0, 14.4, -1.2) * ANG(0, math.pi, 0) * ANG(0, math.pi, 0), V3(26, 4, 0.6), Color3.fromRGB(34, 32, 38), CREAM)
	for _, dx in { -29, 29 } do
		Build.part(m, { name = "Wing", size = V3(2, 18, 14), cf = wallCF * CF(dx, 9.6, -7), color = Color3.fromRGB(46, 44, 54), material = Enum.Material.Metal, collide = true })
	end
	Build.part(m, { name = "Canopy", size = V3(60, 1.4, 16), cf = wallCF * CF(0, 19.2, -7), color = Color3.fromRGB(58, 56, 66), material = Enum.Material.Metal })
	for i, armId in Arms.Order do
		local def = Arms.Defs[armId]
		local t = (i - 3.5) / 2.5
		local pos = ARMORY + V3(t * 24, 0, 8 - math.abs(t) * 3)
		Build.pillar(m, "Pedestal", V3(pos.X, 0.6, pos.Z), 6, 3, { color = Color3.fromRGB(60, 58, 68), material = Enum.Material.Metal, collide = true })
		Build.disc(m, "PedestalGlow", V3(pos.X, 3.6, pos.Z), 5.4, 0.2, { color = def.palette.glow, neon = true })
		local recipe = ArmBuilder.defaultRecipe(armId)
		recipe.tier = 2
		local display = ArmBuilder.buildDisplay(recipe, "R")
		-- present the arm fist-up above the pedestal
		display:PivotTo(CF(pos.X, 11.2, pos.Z) * ANG(math.pi, 0, 0))
		display.Name = "Display_" .. armId
		for _, d in display:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 then
				d.CanCollide = false
			end
		end
		display.Parent = m
		Build.sign(m, string.upper(def.name), CF(V3(pos.X, 4.5, pos.Z + 2.4)) * ANG(0, math.pi, 0), V3(5.6, 1, 0.3), Color3.fromRGB(30, 28, 34), def.palette.glow)
		local pl = Build.part(m, { name = "PedLight", size = V3(0.5, 0.5, 0.5), cf = CF(pos.X, 9, pos.Z), transparency = 1 })
		Build.light(pl, def.palette.glow, 0.6, 12)
	end
	local console = Build.part(m, { name = "ArmoryConsole", size = V3(8, 4, 3), cf = CF(ARMORY + V3(0, 2.6, -8)), color = Color3.fromRGB(40, 38, 48), material = Enum.Material.Metal, collide = true })
	Build.part(m, { name = "ConsoleScreen", size = V3(7, 1.8, 0.2), cf = CF(ARMORY + V3(0, 4.6, -9.6)) * ANG(math.rad(-20), 0, 0), color = GLOW, neon = true })
	Build.prompt(console, "Open Armory", "The Armory", "Arms", 0, 18)
end

-- Reforge Core (rebirth) ------------------------------------------------------------------------------------------------------

local function buildAltar(parent: Instance)
	local m = Build.model(parent, "ReforgeCore")
	Build.disc(m, "AltarBase", ALTAR + V3(0, 0.6, 0), 30, 1.4, { color = Color3.fromRGB(36, 34, 44), material = Enum.Material.Basalt, collide = true })
	Build.disc(m, "AltarRing", ALTAR + V3(0, 2, 0), 26, 0.2, { color = Color3.fromRGB(190, 120, 255), neon = true })
	Build.disc(m, "AltarInner", ALTAR + V3(0, 2.05, 0), 21, 0.2, { color = Color3.fromRGB(26, 22, 36), material = Enum.Material.Metal })
	ringLine(m, ALTAR, 18, 36, 0.5, Color3.fromRGB(255, 150, 60), 2.3)
	local column = Build.pillar(m, "Column", ALTAR + V3(0, 2, 0), 4, 26, { color = Color3.fromRGB(210, 150, 255), neon = true, transparency = 0.45 })
	Build.light(column, Color3.fromRGB(200, 140, 255), 1.6, 40)
	Build.emitter(column, {
		Rate = 22,
		Lifetime = NumberRange.new(2, 3.5),
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180),
		Color = ColorSequence.new(Color3.fromRGB(230, 180, 255)),
		LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
		Acceleration = Vector3.new(0, 4, 0),
	})
	for i = 0, 5 do
		local a = (i / 6) * math.pi * 2
		local p = ALTAR + V3(math.cos(a) * 14, 0, math.sin(a) * 14)
		Build.part(m, { name = "Pylon", size = V3(2.2, 12, 2.2), cf = CF(p + V3(0, 8, 0)) * ANG(0, -a, 0), color = Color3.fromRGB(44, 40, 56), material = Enum.Material.Metal, collide = true })
		Build.part(m, { name = "PylonTip", size = V3(1.2, 2.4, 1.2), cf = CF(p + V3(0, 15, 0)), color = Color3.fromRGB(210, 150, 255), neon = true })
	end
	local trigger = Build.part(m, { name = "AltarTrigger", size = V3(12, 1, 12), cf = CF(ALTAR + V3(0, 2.2, 14)), transparency = 1 })
	Build.tag(trigger, "RebirthAltar")
	Build.prompt(trigger, "Reforge", "Reforge Core", "Rebirth", 0, 22)
	Build.sign(m, "REFORGE CORE", CF(ALTAR + V3(0, 6, 17)) * ANG(0, math.pi, 0), V3(14, 2.6, 0.5), Color3.fromRGB(34, 28, 44), Color3.fromRGB(226, 190, 255))
	Build.part(m, { name = "SignPost", size = V3(0.8, 5, 0.8), cf = CF(ALTAR + V3(0, 2.6, 17)), color = IRON, material = Enum.Material.Metal })
end

-- Skyport -----------------------------------------------------------------------------------------------------------------------

function Forgeheart.skyport(parent: Instance, pos: Vector3, label: string, accent: Color3, faceYaw: number)
	local m = Build.model(parent, "Skyport")
	local cf = CF(pos) * ANG(0, faceYaw, 0)
	Build.disc(m, "Pad", pos + V3(0, 0.55, 0), 34, 1.2, { color = Color3.fromRGB(58, 56, 66), material = Enum.Material.DiamondPlate, collide = true })
	Build.disc(m, "PadGlow", pos + V3(0, 1.7, 0), 30, 0.1, { color = accent, neon = true })
	Build.disc(m, "PadInner", pos + V3(0, 1.75, 0), 28.4, 0.1, { color = Color3.fromRGB(40, 40, 50), material = Enum.Material.Metal })
	-- gate arch
	for _, dx in { -9, 9 } do
		Build.part(m, { name = "GatePost", size = V3(2.4, 20, 2.4), cf = cf * CF(dx, 11.6, -4), color = STEEL, material = Enum.Material.Metal, collide = true })
		Build.part(m, { name = "GateGlow", size = V3(0.6, 18, 0.6), cf = cf * CF(dx * 0.86, 11.6, -4.6), color = accent, neon = true })
	end
	Build.part(m, { name = "GateTop", size = V3(24, 2.6, 3), cf = cf * CF(0, 22.6, -4), color = IRON, material = Enum.Material.Metal })
	Build.sign(m, label, cf * CF(0, 22.6, -5.6) * ANG(0, math.pi, 0), V3(20, 2, 0.4), Color3.fromRGB(30, 28, 34), accent)
	-- the portal curtain
	local curtain = Build.part(m, { name = "Portal", size = V3(15, 17, 0.4), cf = cf * CF(0, 11, -4), color = accent, neon = true, transparency = 0.7 })
	Build.light(curtain, accent, 1.2, 36)
	-- airship moored behind the gate
	local ship = Build.model(m, "Airship")
	local hullCF = cf * CF(22, 7, -10) * ANG(0, math.rad(20), 0)
	Build.part(ship, { name = "Hull", size = V3(8, 4, 22), cf = hullCF, color = Color3.fromRGB(92, 62, 44), material = Enum.Material.WoodPlanks })
	Build.part(ship, { name = "Bow", size = V3(8, 4, 5), cf = hullCF * CF(0, 0, -13) * ANG(0, math.pi, 0), color = Color3.fromRGB(92, 62, 44), material = Enum.Material.WoodPlanks, shape = "Wedge" })
	Build.part(ship, { name = "Balloon", size = V3(14, 9, 26), cf = hullCF * CF(0, 11, 0), color = accent:Lerp(Color3.new(1, 1, 1), 0.35), material = Enum.Material.Fabric, shape = "Ball" })
	for _, dx in { -3, 3 } do
		Build.part(ship, { name = "Rope", size = V3(0.2, 8, 0.2), cf = hullCF * CF(dx, 6, 0), color = Color3.fromRGB(60, 50, 40) })
	end
	local lamp2 = Build.part(ship, { name = "ShipLamp", size = V3(1, 1, 1), cf = hullCF * CF(0, 3, -9), color = accent, neon = true, shape = "Ball" })
	Build.light(lamp2, accent, 0.8, 20)
	-- terminal
	local term = Build.part(m, { name = "SkyportTerminal", size = V3(7, 4.4, 3), cf = cf * CF(-14, 3.2, 6), color = Color3.fromRGB(40, 38, 48), material = Enum.Material.Metal, collide = true })
	Build.part(m, { name = "TerminalScreen", size = V3(6, 2, 0.2), cf = cf * CF(-14, 5, 4.4) * ANG(math.rad(-15), 0, 0), color = accent, neon = true })
	Build.tag(term, "Skyport")
	Build.prompt(term, "Plan a voyage", "Skyport", "Islands", 0, 20)
	return m
end

-- Distant landmarks ----------------------------------------------------------------------------------------------------------------

local function buildLandmarks(parent: Instance)
	local m = Build.model(parent, "Landmarks")
	-- smokestacks along the rim of the island
	for i = 1, 6 do
		local a = math.rad(200 + i * 22)
		local x, z = math.cos(a) * 190, math.sin(a) * 190
		local y = Build.groundY(x, z)
		if y then
			local h = 40 + Build.hash(i, 2) * 24
			local stack = Build.pillar(m, "Smokestack", V3(x, y - 2, z), 7, h, { color = Color3.fromRGB(70, 64, 72), material = Enum.Material.Brick })
			Build.pillar(m, "StackBand", V3(x, y + h - 6, z), 7.6, 1.2, { color = GLOW, neon = true })
			Build.emitter(stack, {
				Rate = 6,
				Lifetime = NumberRange.new(6, 9),
				Speed = NumberRange.new(4, 8),
				Color = ColorSequence.new(Color3.fromRGB(64, 60, 66)),
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(1, 22) }),
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }),
				Acceleration = Vector3.new(2, 1, 0),
			})
		end
	end
end

function Forgeheart.build(folder: Folder, ctx: any)
	buildForge(folder)
	buildHalo(folder)
	buildPlaza(folder, ctx)
	buildFields(folder)
	buildTraining(folder)
	buildArmory(folder)
	buildAltar(folder)
	Forgeheart.skyport(folder, SKYPORT, "SKYPORT", Color3.fromRGB(110, 210, 255), math.rad(200))
	buildLandmarks(folder)
end

return Forgeheart
