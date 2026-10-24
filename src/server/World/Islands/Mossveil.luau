--!strict
-- MOSSVEIL JUNGLE (biome 2): a drowned-green jungle with a big lake, a waterfall off a rock cliff, giant and small trees, bushes and
-- ferns, mossy rocks, hanging vines, a vine-curtained gate and the Rootmother's seal ringed by standing stones.
--
-- Swing vines: twelve of them hang round the jungle; each swing has a 2% chance to fling you to the Canopy Grove (Services/VineService).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local IslandConfig = require(Shared.Config.Islands)
local Build = require(script.Parent.Parent.Build)
local Flora = require(script.Parent.Parent.Flora)
local IslandTerrain = require(script.Parent.Parent.IslandTerrain)
local Forgeheart = require(script.Parent.Forgeheart)

local Mossveil = {}

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles

local DEF = IslandConfig.Defs.Mossveil
local C = DEF.center
local ACCENT = DEF.accent
local GUARDIAN = assert(DEF.guardian, "Mossveil has a guardian")

local SPAWN = V3(C.X, 0, C.Z + 96)
local SKYPORT = V3(C.X - 40, 0, C.Z + 102)
local LAKE = V3(C.X + 64, 0, C.Z + 10)
local CLIFF = V3(C.X + 120, 0, C.Z - 70)
local FERN = DEF.fields[1].center
local TERRACE = DEF.fields[2].center
local SEAL = GUARDIAN.position
local GATE = V3(C.X, 0, C.Z + 52)
local WORLD_TREE = V3(C.X - 112, 0, C.Z - 84)

local MOSS = Color3.fromRGB(72, 116, 60)
local BARK = Color3.fromRGB(88, 66, 48)
local LEAVES = { Color3.fromRGB(52, 108, 56), Color3.fromRGB(66, 124, 60), Color3.fromRGB(44, 94, 62), Color3.fromRGB(86, 140, 64) }
local FERNS = { Color3.fromRGB(60, 130, 62), Color3.fromRGB(80, 150, 70) }
local TREE: Flora.TreeOpts = { trunk = BARK, leaves = LEAVES }

function Mossveil.features(): { IslandTerrain.Feature }
	return {
		{ kind = "flat", pos = SPAWN, radius = 66, target = 0.6, material = Enum.Material.Grass },
		{ kind = "flat", pos = FERN, radius = 58, target = 0.6, material = Enum.Material.LeafyGrass },
		{ kind = "flat", pos = TERRACE, radius = 50, target = 0.6, material = Enum.Material.Slate },
		{ kind = "flat", pos = SEAL, radius = 40, target = 0.6, material = Enum.Material.Ground },
		-- the big lake, deep enough that the island's sea level floods it
		{ kind = "pit", pos = LAKE, radius = 64, height = 12, material = Enum.Material.Ground },
		-- the waterfall cliff
		{ kind = "hill", pos = CLIFF, radius = 38, height = 46, material = Enum.Material.Rock },
		{ kind = "ridge", pos = V3(C.X + 40, 0, C.Z - 165), radius = 30, height = 22, angle = 0, length = 220 },
		{ kind = "hill", pos = V3(C.X - 150, 0, C.Z - 120), radius = 40, height = 14 },
		{ kind = "hill", pos = V3(C.X + 150, 0, C.Z + 60), radius = 36, height = 11 },
		{ kind = "hill", pos = V3(C.X - 120, 0, C.Z + 130), radius = 30, height = 8 },
	}
end

-- helpers -----------------------------------------------------------------------------------------------------------------

local function signPost(parent: Instance, text: string, pos: Vector3, yaw: number)
	local cf = CF(pos) * ANG(0, yaw, 0)
	for _, dx in { -5.5, 5.5 } do
		Build.part(parent, { name = "SignPost", size = V3(0.7, 8, 0.7), cf = cf * CF(dx, 4, 0), color = BARK, material = Enum.Material.Wood, collide = true })
	end
	Build.sign(parent, text, cf * CF(0, 7, 0.2) * ANG(0, math.pi, 0), V3(13, 2.4, 0.5), Color3.fromRGB(28, 44, 32), Color3.fromRGB(220, 255, 200))
end

local function torch(parent: Instance, pos: Vector3)
	Build.pillar(parent, "TorchPole", pos, 0.5, 6, { color = Color3.fromRGB(120, 96, 60), material = Enum.Material.Wood })
	local flame = Build.part(parent, { name = "TorchFlame", size = V3(1.1, 1.6, 1.1), cf = CF(pos + V3(0, 6.6, 0)), color = Color3.fromRGB(160, 255, 140), neon = true, shape = "Ball" })
	Build.light(flame, Color3.fromRGB(160, 255, 150), 1.1, 22)
end

local function fireflies(parent: Instance, pos: Vector3, size: Vector3)
	local box = Build.part(parent, { name = "Fireflies", size = size, cf = CF(pos + V3(0, size.Y / 2, 0)), transparency = 1 })
	Build.emitter(box, {
		Rate = 3,
		Lifetime = NumberRange.new(4, 7),
		Speed = NumberRange.new(0.4, 1.4),
		SpreadAngle = Vector2.new(180, 180),
		Color = ColorSequence.new(Color3.fromRGB(200, 255, 130)),
		LightEmission = 1,
		Size = NumberSequence.new(0.35),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0), NumberSequenceKeypoint.new(0.8, 0), NumberSequenceKeypoint.new(1, 1) }),
	})
end

-- Gate: two giant logs and a lintel, curtained in vines -----------------------------------------------------------------------

local function buildGate(parent: Instance)
	local m = Build.model(parent, "VineGate")
	local gy = Build.groundY(GATE.X, GATE.Z) or 0.6
	for _, dx in { -17, 17 } do
		Build.pillar(m, "GateLog", V3(GATE.X + dx, gy - 1, GATE.Z), 3.6, 28, { color = BARK, material = Enum.Material.Wood, collide = true })
		Build.part(m, { name = "GateMoss", size = V3(3.4, 1.2, 3.4), cf = CF(GATE.X + dx, gy + 27, GATE.Z), color = MOSS, material = Enum.Material.Grass, shape = "Ball" })
		Flora.broadleaf(m, V3(GATE.X + dx * 1.35, gy, GATE.Z - 2), 14, math.floor(dx), TREE)
	end
	Build.part(m, { name = "Lintel", size = V3(40, 3, 3), cf = CF(GATE.X, gy + 25, GATE.Z), color = Color3.fromRGB(76, 58, 42), material = Enum.Material.Wood })
	Build.part(m, { name = "LintelMoss", size = V3(38, 1, 3.4), cf = CF(GATE.X, gy + 26.8, GATE.Z), color = MOSS, material = Enum.Material.Grass })
	for k = 0, 10 do
		local x = GATE.X - 17 + k * 3.4
		Flora.vine(m, V3(x, gy + 24, GATE.Z + 1.2), 7 + Build.hash(k, 4) * 12, k + 7, Color3.fromRGB(58, 104, 54))
	end
	Build.sign(m, "MOSSVEIL JUNGLE", CF(GATE.X, gy + 20, GATE.Z + 1.8) * ANG(0, math.pi, 0), V3(22, 2.8, 0.5), Color3.fromRGB(26, 44, 30), Color3.fromRGB(220, 255, 200))
	for _, dx in { -7, 7 } do
		Build.part(m, { name = "SignChain", size = V3(0.25, 4.6, 0.25), cf = CF(GATE.X + dx, gy + 22.7, GATE.Z + 1.8), color = Color3.fromRGB(40, 40, 40) })
	end
end

-- Lake, lily pads, reeds and a small raft ---------------------------------------------------------------------------------------

local function buildLake(parent: Instance)
	local m = Build.model(parent, "Lake")
	for i = 1, 26 do
		local a = Build.hash(i, 31) * math.pi * 2
		local r = Build.hash(i, 32) * 36
		local x, z = LAKE.X + math.cos(a) * r, LAKE.Z + math.sin(a) * r
		if Build.groundY(x, z) == nil then
			local d = 2.4 + Build.hash(i, 33) * 2.4
			Build.disc(m, "LilyPad", V3(x, -1.52, z), d, 0.1, { color = Color3.fromRGB(70, 132, 62), material = Enum.Material.Grass })
			if i % 3 == 0 then
				Build.part(m, { name = "Lotus", size = V3(0.9, 0.7, 0.9), cf = CF(x, -1.2, z), color = Color3.fromRGB(255, 160, 200), material = Enum.Material.SmoothPlastic, shape = "Ball" })
			end
		end
	end
	Flora.scatter({
		center = LAKE, radius = 58, count = 44, seed = 61, minY = -1.3, maxY = 0.4, tries = 30,
		make = function(pos, i, rnd)
			Flora.tuft(m, pos, 3.5 + rnd * 3, i, Color3.fromRGB(80, 140, 70))
		end,
	})
	-- a raft with a lantern, tied up at the shallow end
	local rx, rz = LAKE.X - 14, LAKE.Z + 26
	if Build.groundY(rx, rz) == nil then
		for k = -3, 3 do
			Build.part(m, { name = "RaftLog", size = V3(7, 1.2, 1.2), cf = CF(rx + k * 1.3, -1.3, rz + 3.5) * ANG(0, math.pi / 2, 0), color = Color3.fromRGB(104, 78, 54), material = Enum.Material.Wood, shape = "Cylinder" })
		end
		Build.part(m, { name = "RaftDeck", size = V3(9, 0.3, 6), cf = CF(rx, -0.75, rz + 3.5), color = Color3.fromRGB(122, 90, 60), material = Enum.Material.WoodPlanks })
		Build.part(m, { name = "RaftPost", size = V3(0.4, 4, 0.4), cf = CF(rx + 3.5, 1.4, rz + 3.5), color = BARK, material = Enum.Material.Wood })
		local lamp = Build.part(m, { name = "RaftLantern", size = V3(1, 1.2, 1), cf = CF(rx + 3.5, 3.8, rz + 3.5), color = Color3.fromRGB(160, 255, 150), neon = true })
		Build.light(lamp, Color3.fromRGB(160, 255, 150), 1.1, 20)
	end
	fireflies(m, V3(LAKE.X - 30, 0, LAKE.Z + 40), V3(30, 8, 30))
	fireflies(m, V3(LAKE.X + 30, 0, LAKE.Z - 36), V3(28, 8, 28))
end

-- Waterfall: a sheet of water laid along the cliff face down into the lake -------------------------------------------------------

local function buildWaterfall(parent: Instance)
	local m = Build.model(parent, "Waterfall")
	local flat = V3(LAKE.X - CLIFF.X, 0, LAKE.Z - CLIFF.Z)
	local dir = flat.Unit
	local pts: { Vector3 } = {}
	for d = 0, 100, 3 do
		local x, z = CLIFF.X + dir.X * d, CLIFF.Z + dir.Z * d
		local y = Build.groundY(x, z)
		if y == nil or y < -1.0 then
			break
		end
		table.insert(pts, V3(x, y + 0.45, z))
	end
	if #pts < 3 then
		warn("[ARMFORGE] Mossveil waterfall found no slope to follow")
		return
	end
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local len = (b - a).Magnitude + 0.4
		local width = 9 - 3 * (i / #pts)
		Build.part(m, { name = "WaterSheet", size = V3(width, 0.4, len), cf = CFrame.lookAt((a + b) / 2, b), color = Color3.fromRGB(170, 224, 246), material = Enum.Material.Glass, transparency = 0.28 })
		Build.part(m, { name = "WaterStreak", size = V3(width * 0.35, 0.44, len), cf = CFrame.lookAt((a + b) / 2, b) * CF(((i % 3) - 1) * width * 0.25, 0.02, 0), color = Color3.fromRGB(240, 252, 255), neon = true, transparency = 0.5 })
	end
	local top, base = pts[1], pts[#pts]
	-- mist and foam where it meets the lake, a glow at the lip
	local foam = Build.disc(m, "Foam", V3(base.X, -1.5, base.Z), 16, 0.12, { color = Color3.fromRGB(235, 248, 252), material = Enum.Material.Foil, transparency = 0.25 })
	Build.emitter(foam, {
		Rate = 14,
		Lifetime = NumberRange.new(2.5, 4),
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(40, 40),
		Color = ColorSequence.new(Color3.fromRGB(235, 248, 255)),
		LightEmission = 0.3,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 14) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) }),
		Acceleration = Vector3.new(0, 1.5, 0),
		EmissionDirection = Enum.NormalId.Top,
	})
	local lip = Build.part(m, { name = "LipGlow", size = V3(1, 1, 1), cf = CF(top + V3(0, 3, 0)), transparency = 1 })
	Build.light(lip, Color3.fromRGB(190, 240, 255), 0.8, 30)
	for k = 1, 6 do
		local a = Build.hash(k, 77) * math.pi * 2
		Flora.mossRock(m, V3(base.X + math.cos(a) * 11, -0.6, base.Z + math.sin(a) * 11), 3 + Build.hash(k, 78) * 2.5, k + 400)
	end
end

-- Guardian clearing: standing stones, roots and runes round the Rootmother's seal ----------------------------------------------

local function buildClearing(parent: Instance)
	local m = Build.model(parent, "RootClearing")
	local gy = Build.groundY(SEAL.X, SEAL.Z) or 0.6
	for i = 0, 7 do
		local a = (i / 8) * math.pi * 2
		local p = V3(SEAL.X + math.cos(a) * 27, gy, SEAL.Z + math.sin(a) * 27)
		local h = 8 + Build.hash(i, 5) * 5
		local stone = Build.part(m, { name = "StandingStone", size = V3(3.4, h, 2.4), cf = CF(p + V3(0, h / 2 - 0.5, 0)) * ANG(0.05 * (i % 3 - 1), -a, 0.04), color = Color3.fromRGB(104, 108, 100), material = Enum.Material.Rock, collide = true })
		Build.part(m, { name = "StoneMoss", size = V3(3.6, 1.6, 2.6), cf = CF(p + V3(0, h - 0.8, 0)) * ANG(0, -a, 0), color = MOSS, material = Enum.Material.Grass })
		local rune = Build.part(m, { name = "Rune", size = V3(0.18, h * 0.5, 1.1), cf = CF(p + V3(0, h * 0.5, 0)) * ANG(0, -a, 0) * CF(-stone.Size.X / 2 - 0.05, 0, 0), color = Color3.fromRGB(150, 255, 130), neon = true })
		if i % 2 == 0 then
			Build.light(rune, Color3.fromRGB(150, 255, 130), 0.7, 14)
		end
	end
	-- roots creeping across the clearing floor toward the seal
	for i = 0, 11 do
		local a = (i / 12) * math.pi * 2 + 0.2
		local len = 14 + Build.hash(i, 9) * 8
		Build.part(m, { name = "Root", size = V3(len, 0.9, 0.9), cf = CF(SEAL.X + math.cos(a) * (12 + len / 2), gy + 0.1, SEAL.Z + math.sin(a) * (12 + len / 2)) * ANG(0, -a, 0), color = BARK, material = Enum.Material.Wood, shape = "Cylinder" })
	end
	fireflies(m, V3(SEAL.X, gy, SEAL.Z), V3(50, 9, 50))
	Build.sign(m, "ROOTMOTHER'S GLADE", CF(SEAL.X + 34, gy + 6.5, SEAL.Z) * ANG(0, -math.pi / 2, 0), V3(16, 2.2, 0.4), Color3.fromRGB(26, 44, 30), Color3.fromRGB(190, 255, 150))
	Build.part(m, { name = "GladePostA", size = V3(0.6, 6.4, 0.6), cf = CF(SEAL.X + 34, gy + 3.2, SEAL.Z - 6), color = BARK, material = Enum.Material.Wood })
	Build.part(m, { name = "GladePostB", size = V3(0.6, 6.4, 0.6), cf = CF(SEAL.X + 34, gy + 3.2, SEAL.Z + 6), color = BARK, material = Enum.Material.Wood })
end

-- Flora ---------------------------------------------------------------------------------------------------------------------------

local function buildFlora(parent: Instance)
	local m = Build.model(parent, "Flora")
	local avoid: { Flora.Zone } = {
		{ pos = SPAWN, radius = 74 },
		{ pos = SKYPORT, radius = 40 },
		{ pos = FERN, radius = 56 },
		{ pos = TERRACE, radius = 48 },
		{ pos = SEAL, radius = 40 },
		{ pos = GATE, radius = 30 },
		{ pos = CLIFF, radius = 22 },
		{ pos = V3(C.X, 0, C.Z + 75), radius = 22 },
	}
	-- the giant at the back of the island, visible from everywhere
	local wy = Build.groundY(WORLD_TREE.X, WORLD_TREE.Z)
	if wy then
		Flora.jungleTree(m, V3(WORLD_TREE.X, wy, WORLD_TREE.Z), 86, 9001, { trunk = Color3.fromRGB(84, 62, 46), leaves = LEAVES }, true)
	end
	Flora.scatter({
		center = C, radius = 170, count = 58, seed = 500, minY = 0.1, maxY = 24, avoid = avoid, spacing = 17,
		make = function(pos, i, rnd)
			Flora.jungleTree(m, pos, 24 + rnd * 18, i, TREE, i % 3 == 0)
		end,
	})
	Flora.scatter({
		center = C, radius = 180, count = 70, seed = 600, minY = 0.1, maxY = 24, avoid = avoid, spacing = 7,
		make = function(pos, i, rnd)
			Flora.sapling(m, pos, 6 + rnd * 5, i, TREE)
		end,
	})
	Flora.scatter({
		center = C, radius = 185, count = 90, seed = 700, minY = 0.1, maxY = 24, avoid = avoid, spacing = 4,
		make = function(pos, i, rnd)
			if i % 2 == 0 then
				Flora.bush(m, pos, 2.6 + rnd * 2, i, LEAVES, if i % 5 == 0 then Color3.fromRGB(255, 130, 170) else nil)
			else
				Flora.fern(m, pos, 4 + rnd * 3, i, FERNS[1 + i % 2])
			end
		end,
	})
	Flora.scatter({
		center = C, radius = 180, count = 34, seed = 800, minY = 0.1, maxY = 24, avoid = avoid, spacing = 9,
		make = function(pos, i, rnd)
			Flora.mossRock(m, pos, 3 + rnd * 4, i)
		end,
	})
	-- fallen logs
	Flora.scatter({
		center = C, radius = 170, count = 12, seed = 900, minY = 0.1, maxY = 10, avoid = avoid, spacing = 20,
		make = function(pos, i, rnd)
			local len = 9 + rnd * 8
			Build.part(m, { name = "FallenLog", size = V3(len, 2, 2), cf = CF(pos + V3(0, 0.8, 0)) * ANG(0, i, 0), color = BARK, material = Enum.Material.Wood, shape = "Cylinder", collide = true })
			Build.part(m, { name = "LogMoss", size = V3(len * 0.7, 0.6, 1.8), cf = CF(pos + V3(0, 1.7, 0)) * ANG(0, i, 0), color = MOSS, material = Enum.Material.Grass })
		end,
	})
end

-- Swing vines: a pole, a branch and a rope you can swing on; the rope's model sways when used ------------------------------------------------------

local function buildSwingVines(parent: Instance)
	local m = Build.model(parent, "SwingVines")
	local avoid: { Flora.Zone } = {
		{ pos = SPAWN, radius = 70 },
		{ pos = SKYPORT, radius = 40 },
		{ pos = FERN, radius = 54 },
		{ pos = TERRACE, radius = 46 },
		{ pos = SEAL, radius = 44 },
		{ pos = GATE, radius = 26 },
		{ pos = CLIFF, radius = 24 },
		{ pos = LAKE, radius = 56 },
	}
	Flora.scatter({
		center = C, radius = 128, count = 12, seed = 6100, minY = 0.2, maxY = 8, avoid = avoid, spacing = 26,
		make = function(pos, i, rnd)
			local yaw = rnd * math.pi * 2
			local top = pos + V3(0, 11, 0)
			Build.pillar(m, "VinePole", pos + V3(0, -0.4, 0), 1.1, 11.4, { color = BARK, material = Enum.Material.Wood, collide = true })
			local arm = CF(top) * ANG(0, yaw, 0)
			Build.part(m, { name = "VineBranch", size = V3(7, 0.8, 0.8), cf = arm * CF(3.2, 0, 0), color = BARK, material = Enum.Material.Wood })
			Flora.bush(m, top + V3(0, 0.6, 0), 4, i, LEAVES)
			-- the rope is its own model, pivoting where it meets the branch, so the service can sway it
			local rope = Build.model(m, "SwingVine")
			local hinge = (arm * CF(6.4, 0, 0)).Position
			local pivot = Build.part(rope, { name = "Hinge", size = V3(0.4, 0.4, 0.4), cf = CF(hinge), transparency = 1 })
			rope.PrimaryPart = pivot
			Build.part(rope, { name = "Rope", size = V3(0.35, 9, 0.35), cf = CF(hinge + V3(0, -4.5, 0)), color = Color3.fromRGB(74, 122, 60), material = Enum.Material.Grass })
			Build.part(rope, { name = "Knot", size = V3(1, 1, 1), cf = CF(hinge + V3(0, -9.2, 0)), color = Color3.fromRGB(110, 170, 80), material = Enum.Material.Grass, shape = "Ball" })
			for k = 1, 4 do
				Build.part(rope, { name = "VineLeaf", size = V3(1.6, 0.12, 1.1), cf = CF(hinge + V3(0, -1.4 - k * 1.8, 0)) * ANG(0, k * 1.3, 0.5 * (if k % 2 == 0 then 1 else -1)), color = Color3.fromRGB(110, 170, 80), material = Enum.Material.LeafyGrass })
			end
			local grip = Build.part(rope, { name = "Grip", size = V3(2.4, 2, 2.4), cf = CF(hinge + V3(0, -8.4, 0)), transparency = 1 })
			local p = Instance.new("ProximityPrompt")
			p.ActionText = "Swing"
			p.ObjectText = "Jungle vine"
			p.HoldDuration = 0
			p.MaxActivationDistance = 14
			p.RequiresLineOfSight = false
			p.KeyboardKeyCode = Enum.KeyCode.E
			p.Parent = grip
			Build.tag(grip, "SwingVine")
		end,
	})
	-- a hint at the gate, in the jungle's own words
	local gy = Build.groundY(SPAWN.X + 22, SPAWN.Z - 24) or 0.6
	Build.sign(m, "SWING VINES  ·  who knows where one leads?", CF(SPAWN.X + 22, gy + 6, SPAWN.Z - 24) * ANG(0, math.pi, 0), V3(20, 2.2, 0.4), Color3.fromRGB(28, 44, 32), Color3.fromRGB(220, 255, 200))
	Build.part(m, { name = "HintPost", size = V3(0.6, 6, 0.6), cf = CF(SPAWN.X + 22, gy + 3, SPAWN.Z - 24), color = BARK, material = Enum.Material.Wood })
end

-- Island -------------------------------------------------------------------------------------------------------------------------

function Mossveil.build(folder: Folder, ctx: any)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "MossveilSpawn"
	spawn.Anchored = true
	spawn.Size = V3(12, 1, 12)
	spawn.CFrame = CF(V3(SPAWN.X, 1.1, SPAWN.Z))
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Material = Enum.Material.Slate
	spawn.Color = Color3.fromRGB(66, 82, 62)
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = folder
	ctx.spawn("Mossveil", spawn)
	Forgeheart.skyport(folder, SKYPORT, "SKYPORT: RETURN", ACCENT, math.rad(200))

	-- torch-lit path from the spawn to the gate and the fields
	local path = Build.model(folder, "Path")
	for k = 0, 4 do
		local z = SPAWN.Z - 12 - k * 11
		for _, dx in { -9, 9 } do
			local y = Build.groundY(SPAWN.X + dx, z)
			if y then
				torch(path, V3(SPAWN.X + dx, y, z))
			end
		end
	end
	buildGate(folder)
	buildLake(folder)
	buildWaterfall(folder)
	buildClearing(folder)
	local signs = Build.model(folder, "FieldSigns")
	signPost(signs, "FERN HOLLOW", V3(FERN.X + 10, Build.groundY(FERN.X + 10, FERN.Z + 56) or 0.6, FERN.Z + 56), 0)
	signPost(signs, "JADE TERRACE", V3(TERRACE.X + 8, Build.groundY(TERRACE.X + 8, TERRACE.Z + 48) or 0.6, TERRACE.Z + 48), 0)
	buildFlora(folder)
	buildSwingVines(folder)
end

return Mossveil
