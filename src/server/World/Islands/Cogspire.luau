--!strict
-- COGSPIRE FOUNDRY (biome 5, steampunk): a brass-and-brick foundry city under a haze of steam. A gear gate opens onto cobbled streets that
-- lead to the Great Clock; the sealed engine room at its foot is the Valve Seal. Rooftop gears turn (client-side, via the Spin tag), pipes
-- cross the yards on pylons and leak steam, chimneys smoke, and airships hang over the roofs. Rocks sit in the Boiler Yard and the Aether Works.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local IslandConfig = require(Shared.Config.Islands)
local Build = require(script.Parent.Parent.Build)
local Flora = require(script.Parent.Parent.Flora)
local Road = require(script.Parent.Parent.Road)
local IslandTerrain = require(script.Parent.Parent.IslandTerrain)
local Forgeheart = require(script.Parent.Forgeheart)

local Cogspire = {}

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles

local DEF = IslandConfig.Defs.Cogspire
local C = DEF.center
local ACCENT = DEF.accent
local GUARDIAN = assert(DEF.guardian, "Cogspire has a guardian")

local SPAWN = V3(C.X, 0, C.Z + 96)
local SKYPORT = V3(C.X - 40, 0, C.Z + 102)
local GATE = V3(C.X, 0, C.Z + 60)
local TOWER = V3(C.X, 0, C.Z - 50)
local SEAL = V3(GUARDIAN.position.X, 0, GUARDIAN.position.Z)
local YARD = DEF.fields[1].center
local WORKS = DEF.fields[2].center
local PLATFORM_Y = 6.6

local BRASS = Color3.fromRGB(196, 146, 66)
local DARK_BRASS = Color3.fromRGB(110, 78, 40)
local COPPER = Color3.fromRGB(176, 98, 62)
local BRICK = Color3.fromRGB(122, 70, 54)
local IRON = Color3.fromRGB(58, 56, 62)
local CREAM = Color3.fromRGB(255, 232, 190)
local STEAM = Color3.fromRGB(235, 240, 244)
local GLOW = Color3.fromRGB(255, 190, 90)
local AETHER = Color3.fromRGB(130, 235, 255)

function Cogspire.features(): { IslandTerrain.Feature }
	return {
		{ kind = "mound", pos = TOWER, radius = 80, height = PLATFORM_Y - 0.6, length = 54 },
		{ kind = "ridge", pos = V3(C.X, 0, C.Z - 150), radius = 24, height = 12, angle = 0, length = 130 },
		{ kind = "flat", pos = SPAWN, radius = 50, target = 0.6, material = Enum.Material.Pavement },
		{ kind = "flat", pos = GATE, radius = 24, target = 0.6, material = Enum.Material.Cobblestone },
		{ kind = "flat", pos = YARD, radius = 58, target = 0.6, material = Enum.Material.Pavement },
		{ kind = "flat", pos = WORKS, radius = 44, target = 0.6, material = Enum.Material.Pavement },
		{ kind = "flat", pos = TOWER, radius = 58, target = PLATFORM_Y, material = Enum.Material.Pavement },
	}
end

-- building blocks -------------------------------------------------------------------------------------------------------------------

local function groundAt(x: number, z: number): number
	return Build.groundY(x, z) or 0.6
end

local function steamEmitter(part: BasePart, rate: number, size: number)
	Build.emitter(part, {
		Rate = rate,
		Lifetime = NumberRange.new(1.5, 3),
		Speed = NumberRange.new(3, 6),
		SpreadAngle = Vector2.new(18, 18),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-30, 30),
		Color = ColorSequence.new(STEAM),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.4), NumberSequenceKeypoint.new(1, size) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }),
		Acceleration = Vector3.new(0.5, 2, 0),
		EmissionDirection = Enum.NormalId.Top,
	})
end

-- A toothed gear. Its axle is the frame's local Z. With `speed` it carries the Spin tag, so clients turn it (AtmosphereController).
local function gear(parent: Instance, center: Vector3, orient: CFrame, radius: number, teeth: number, thick: number, color: Color3, speed: number?): Model
	local m = Build.model(parent, "Gear")
	local f = CF(center) * orient
	local axle = Build.part(m, { name = "Axle", size = V3(0.6, 0.6, thick + 0.4), cf = f, color = DARK_BRASS, material = Enum.Material.Metal })
	m.PrimaryPart = axle
	Build.part(m, { name = "Hub", size = V3(thick + 0.6, radius * 0.36, radius * 0.36), cf = f * ANG(0, math.pi / 2, 0), color = DARK_BRASS, material = Enum.Material.Metal, shape = "Cylinder" })
	for i = 0, teeth - 1 do
		local a = (i / teeth) * math.pi * 2
		local at = f * CF(math.cos(a) * radius, math.sin(a) * radius, 0) * ANG(0, 0, a + math.pi / 2)
		Build.part(m, { name = "Rim", size = V3(radius * 2 * math.pi / teeth * 1.08, radius * 0.14, thick), cf = at, color = color, material = Enum.Material.Metal })
		Build.part(m, { name = "Tooth", size = V3(radius * 2 * math.pi / teeth * 0.5, radius * 0.24, thick), cf = at * CF(0, -radius * 0.17, 0), color = color:Lerp(DARK_BRASS, 0.3), material = Enum.Material.Metal })
	end
	for k = 0, 2 do
		Build.part(m, { name = "Spoke", size = V3(radius * 1.9, radius * 0.1, thick * 0.7), cf = f * ANG(0, 0, k * math.pi / 3), color = color, material = Enum.Material.Metal })
	end
	if speed then
		m:SetAttribute("SpinSpeed", speed)
		Build.tag(m, "Spin")
	end
	return m
end

local FLAT = ANG(-math.pi / 2, 0, 0) -- frame whose local Z points up: a gear lying flat, turning about the vertical

local function brick(parent: Instance, name: string, size: Vector3, cf: CFrame, tone: number): BasePart
	return Build.part(parent, { name = name, size = size, cf = cf, color = BRICK:Lerp(IRON, tone), material = Enum.Material.Brick, collide = true })
end

local function windowsOn(parent: Instance, cf: CFrame, width: number, height: number, cols: number, rows: number, seed: number)
	for r = 1, rows do
		for c = 1, cols do
			if Build.hash(seed, r * 17 + c) > 0.25 then
				Build.part(parent, { name = "Window", size = V3(width / (cols * 2.2), height / (rows * 2.6), 0.25), cf = cf * CF(-width / 2 + (c - 0.5) * width / cols, -height / 2 + (r - 0.5) * height / rows, 0), color = GLOW, neon = true })
			end
		end
	end
end

-- A factory block: brick body, window rows, a slanted copper roof or a flat one with a chimney and pipe.
local function building(parent: Instance, pos: Vector3, w: number, d: number, h: number, yaw: number, seed: number)
	local m = Build.model(parent, "Building")
	local gy = groundAt(pos.X, pos.Z)
	local cf = CF(pos.X, gy, pos.Z) * ANG(0, yaw, 0)
	brick(m, "Body", V3(w, h + 1, d), cf * CF(0, h / 2 - 0.5, 0), Build.hash(seed, 1) * 0.5)
	brick(m, "Plinth", V3(w + 1, 1.2, d + 1), cf * CF(0, 0.2, 0), 0.7)
	windowsOn(m, cf * CF(0, h * 0.55, -d / 2 - 0.15) * ANG(0, math.pi, 0), w * 0.8, h * 0.7, math.max(2, math.floor(w / 5)), math.max(2, math.floor(h / 6)), seed)
	windowsOn(m, cf * CF(0, h * 0.55, d / 2 + 0.15), w * 0.8, h * 0.7, math.max(2, math.floor(w / 5)), math.max(2, math.floor(h / 6)), seed + 5)
	if Build.hash(seed, 2) > 0.45 then
		Build.part(m, { name = "Roof", size = V3(w + 2, 1, d + 2), cf = cf * CF(0, h + 0.5, 0), color = COPPER, material = Enum.Material.Metal })
		Build.part(m, { name = "RoofRidgeA", size = V3(w + 2, d * 0.35, d * 0.55), cf = cf * CF(0, h + d * 0.17, -d * 0.2) * ANG(0.5, 0, 0), color = COPPER, material = Enum.Material.Metal })
		Build.part(m, { name = "RoofRidgeB", size = V3(w + 2, d * 0.35, d * 0.55), cf = cf * CF(0, h + d * 0.17, d * 0.2) * ANG(-0.5, 0, 0), color = COPPER, material = Enum.Material.Metal })
	else
		Build.part(m, { name = "Parapet", size = V3(w + 1, 1.2, d + 1), cf = cf * CF(0, h + 0.8, 0), color = IRON, material = Enum.Material.Metal })
	end
	if Build.hash(seed, 3) > 0.35 then
		local cx, cz = (Build.hash(seed, 4) - 0.5) * w * 0.5, (Build.hash(seed, 5) - 0.5) * d * 0.5
		local top = (cf * CF(cx, h + 1, cz)).Position
		local stack = Build.pillar(m, "Chimney", top, 2.4 + Build.hash(seed, 6), 8 + Build.hash(seed, 7) * 6, { color = IRON, material = Enum.Material.Brick, collide = true })
		Build.pillar(m, "ChimneyBand", top + V3(0, 6, 0), 3, 0.8, { color = BRASS, material = Enum.Material.Metal })
		Build.emitter(stack, {
			Rate = 6,
			Lifetime = NumberRange.new(5, 8),
			Speed = NumberRange.new(4, 7),
			Color = ColorSequence.new(Color3.fromRGB(96, 92, 94)),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 12) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }),
			Acceleration = Vector3.new(2, 1, 0),
		})
	end
	if Build.hash(seed, 8) > 0.5 then
		gear(m, (cf * CF(w / 2 + 0.6, h * 0.55, 0)).Position, ANG(0, yaw + math.pi / 2, 0), 3 + Build.hash(seed, 9) * 2, 12, 0.8, BRASS, nil)
	end
end

-- A pipe run on pylons from a to b at a given height, with valve wheels and a steam leak.
local function pipeRun(parent: Instance, a: Vector3, b: Vector3, height: number, diameter: number, seed: number)
	local ay, by = groundAt(a.X, a.Z), groundAt(b.X, b.Z)
	local pa, pb = V3(a.X, ay + height, a.Z), V3(b.X, by + height, b.Z)
	local len = (pb - pa).Magnitude
	local mid = (pa + pb) / 2
	Build.part(parent, { name = "Pipe", size = V3(len, diameter, diameter), cf = CFrame.lookAt(mid, pb) * ANG(0, math.pi / 2, 0), color = COPPER, material = Enum.Material.Metal, shape = "Cylinder" })
	for _, p in { pa, pb } do
		Build.part(parent, { name = "Elbow", size = V3(diameter * 1.4, diameter * 1.4, diameter * 1.4), cf = CF(p), color = BRASS, material = Enum.Material.Metal, shape = "Ball" })
	end
	local n = math.max(1, math.floor(len / 16))
	for k = 1, n do
		local t = k / (n + 1)
		local p = pa:Lerp(pb, t)
		local g = groundAt(p.X, p.Z)
		Build.part(parent, { name = "Pylon", size = V3(1.2, p.Y - g, 1.2), cf = CF(p.X, g + (p.Y - g) / 2, p.Z), color = IRON, material = Enum.Material.Metal, collide = true })
		Build.part(parent, { name = "Band", size = V3(1.2, diameter * 1.25, diameter * 1.25), cf = CFrame.lookAt(p, pb) * ANG(0, math.pi / 2, 0), color = BRASS, material = Enum.Material.Metal, shape = "Cylinder" })
		if k == 1 then
			Build.part(parent, { name = "ValveWheel", size = V3(0.4, 2.6, 2.6), cf = CF(p + V3(0, diameter * 0.9, 0)) * ANG(0, 0, math.pi / 2), color = Color3.fromRGB(190, 56, 48), material = Enum.Material.Metal, shape = "Cylinder" })
		end
	end
	if Build.hash(seed, 1) > 0.4 then
		local leak = Build.part(parent, { name = "SteamLeak", size = V3(1, 1, 1), cf = CF(pa:Lerp(pb, 0.5) + V3(0, diameter * 0.6, 0)), transparency = 1 })
		steamEmitter(leak, 12, 6)
	end
end

local function gasLamp(parent: Instance, pos: Vector3)
	Build.pillar(parent, "LampPost", pos, 0.6, 8, { color = IRON, material = Enum.Material.Metal })
	local globe = Build.part(parent, { name = "LampGlobe", size = V3(1.8, 1.8, 1.8), cf = CF(pos + V3(0, 8.6, 0)), color = GLOW, neon = true, shape = "Ball" })
	Build.light(globe, GLOW, 1.2, 26)
end

-- Gate: two brass pylons carrying big gears --------------------------------------------------------------------------------------------

local function buildGate(parent: Instance)
	local m = Build.model(parent, "GearGate")
	local gy = groundAt(GATE.X, GATE.Z)
	for k, dx in { -20, 20 } do
		Build.part(m, { name = "GatePylon", size = V3(7, 30, 7), cf = CF(GATE.X + dx, gy + 15, GATE.Z), color = BRICK, material = Enum.Material.Brick, collide = true })
		Build.part(m, { name = "PylonCap", size = V3(9, 2, 9), cf = CF(GATE.X + dx, gy + 31, GATE.Z), color = BRASS, material = Enum.Material.Metal })
		gear(m, V3(GATE.X + dx, gy + 20, GATE.Z - 4.2), CFrame.new(), 7, 14, 1.2, BRASS, if k == 1 then 0.5 else -0.5)
		gear(m, V3(GATE.X + dx, gy + 9, GATE.Z - 4.2), CFrame.new(), 4.4, 10, 1.2, COPPER, if k == 1 then -0.8 else 0.8)
	end
	Build.part(m, { name = "GateBeam", size = V3(48, 4, 4), cf = CF(GATE.X, gy + 27, GATE.Z), color = IRON, material = Enum.Material.Metal })
	Build.sign(m, "COGSPIRE FOUNDRY", CF(GATE.X, gy + 22, GATE.Z + 2.4) * ANG(0, math.pi, 0), V3(26, 3, 0.5), Color3.fromRGB(40, 28, 18), CREAM)
	Build.sign(m, "COGSPIRE FOUNDRY", CF(GATE.X, gy + 22, GATE.Z - 2.4), V3(26, 3, 0.5), Color3.fromRGB(40, 28, 18), CREAM)
end

-- Great Clock and the sealed engine room -------------------------------------------------------------------------------------------------

local function buildClock(parent: Instance)
	local m = Build.model(parent, "GreatClock")
	local by = PLATFORM_Y
	local x, z = TOWER.X, TOWER.Z
	brick(m, "TowerBase", V3(34, 22, 34), CF(x, by + 11, z), 0.2)
	brick(m, "TowerMid", V3(24, 44, 24), CF(x, by + 22 + 22, z), 0.3)
	brick(m, "ClockHouse", V3(30, 22, 30), CF(x, by + 66 + 11, z), 0.15)
	for _, dy in { 22, 66 } do
		Build.part(m, { name = "Cornice", size = V3(37, 2, 37), cf = CF(x, by + dy + 1, z), color = BRASS, material = Enum.Material.Metal })
	end
	-- copper spire
	for k = 0, 4 do
		Build.part(m, { name = "Spire", size = V3(30 - k * 6, 5, 30 - k * 6), cf = CF(x, by + 88 + 2.5 + k * 5, z), color = COPPER, material = Enum.Material.Metal })
	end
	Build.pillar(m, "Mast", V3(x, by + 113, z), 1, 16, { color = BRASS, material = Enum.Material.Metal })
	local beacon = Build.part(m, { name = "Beacon", size = V3(3, 3, 3), cf = CF(x, by + 130, z), color = AETHER, neon = true, shape = "Ball" })
	Build.light(beacon, AETHER, 2, 80)
	-- four clock faces with turning hands
	for k = 0, 3 do
		local yaw = k * math.pi / 2
		local f = CF(x, by + 77, z) * ANG(0, yaw, 0) * CF(0, 0, 15.2)
		Build.part(m, { name = "FaceRim", size = V3(1.2, 21, 21), cf = f * ANG(0, math.pi / 2, 0), color = BRASS, material = Enum.Material.Metal, shape = "Cylinder" })
		Build.part(m, { name = "Face", size = V3(0.6, 19, 19), cf = f * CF(0, 0, 0.5) * ANG(0, math.pi / 2, 0), color = CREAM, material = Enum.Material.SmoothPlastic, shape = "Cylinder" })
		for t = 0, 11 do
			local a = t / 12 * math.pi * 2
			Build.part(m, { name = "Tick", size = V3(0.5, if t % 3 == 0 then 2.4 else 1.4, 0.3), cf = f * CF(math.sin(a) * 8, math.cos(a) * 8, 0.9) * ANG(0, 0, -a), color = IRON, material = Enum.Material.Metal })
		end
		for i, hand in { { 7.4, 0.9, 0.12 }, { 5, 1.2, 0.01 } } do
			local hm = Build.model(m, "ClockHand")
			local hf = f * CF(0, 0, 1.2)
			local axle = Build.part(hm, { name = "Axle", size = V3(0.8, 0.8, 0.4), cf = hf, color = IRON, material = Enum.Material.Metal })
			hm.PrimaryPart = axle
			Build.part(hm, { name = "Hand", size = V3(hand[2], hand[1], 0.3), cf = hf * CF(0, hand[1] / 2, 0.15 * i), color = IRON, material = Enum.Material.Metal })
			hm:SetAttribute("SpinSpeed", -hand[3])
			Build.tag(hm, "Spin")
		end
	end
	-- the engine-room door at the foot of the tower, facing the seal
	local door = Build.part(m, { name = "EngineDoor", size = V3(14, 14, 1.2), cf = CF(x, by + 7, z + 17.4), color = Color3.fromRGB(26, 32, 44), material = Enum.Material.Metal, collide = true })
	Build.light(door, AETHER, 1.1, 30)
	for k = -1, 1 do
		Build.part(m, { name = "DoorSeam", size = V3(0.4, 12, 0.3), cf = CF(x + k * 4, by + 7, z + 18.1), color = AETHER, neon = true })
	end
	for _, y in { 4, 10 } do
		Build.part(m, { name = "DoorBar", size = V3(14.4, 1, 1.4), cf = CF(x, by + y, z + 18.1), color = BRASS, material = Enum.Material.Metal })
	end
	Build.sign(m, "THE ENGINE ROOM", CF(x, by + 17, z + 17.9) * ANG(0, math.pi, 0), V3(16, 2.2, 0.4), Color3.fromRGB(40, 28, 18), CREAM)
	-- rooftop gears on the tower base
	for _, dx in { -9, 9 } do
		gear(m, V3(x + dx, by + 22.8, z + 8), FLAT, 6, 12, 1.4, BRASS, if dx < 0 then 0.6 else -0.6)
	end
end

-- Seal arena: a gear floor ringed by pistons ---------------------------------------------------------------------------------------------

local function buildArena(parent: Instance)
	local m = Build.model(parent, "SealArena")
	local gy = groundAt(SEAL.X, SEAL.Z)
	Build.disc(m, "FloorBrass", V3(SEAL.X, gy + 0.05, SEAL.Z), 46, 0.3, { color = BRASS, material = Enum.Material.Metal })
	Build.disc(m, "FloorPlate", V3(SEAL.X, gy + 0.2, SEAL.Z), 44, 0.2, { color = Color3.fromRGB(70, 56, 44), material = Enum.Material.DiamondPlate })
	Build.disc(m, "AetherRing", V3(SEAL.X, gy + 0.34, SEAL.Z), 34, 0.12, { color = AETHER, neon = true })
	Build.disc(m, "AetherFloor", V3(SEAL.X, gy + 0.4, SEAL.Z), 33.2, 0.12, { color = Color3.fromRGB(70, 56, 44), material = Enum.Material.DiamondPlate })
	gear(m, V3(SEAL.X, gy + 0.6, SEAL.Z), FLAT, 12, 16, 0.4, DARK_BRASS, 0.15)
	for i = 0, 7 do
		local a = (i / 8) * math.pi * 2 + 0.2
		local x, z = SEAL.X + math.cos(a) * 23, SEAL.Z + math.sin(a) * 23
		local y = groundAt(x, z)
		Build.pillar(m, "PistonCasing", V3(x, y, z), 3.4, 9, { color = IRON, material = Enum.Material.Metal, collide = true })
		local rod = Build.pillar(m, "PistonRod", V3(x, y + 9, z), 1.6, 5 + Build.hash(i, 3) * 4, { color = Color3.fromRGB(200, 204, 212), material = Enum.Material.Metal })
		local cap = Build.part(m, { name = "PistonCap", size = V3(2.6, 0.8, 2.6), cf = CF(x, y + 14.4 + Build.hash(i, 3) * 4, z), color = AETHER, neon = true })
		if i % 2 == 0 then
			Build.light(cap, AETHER, 0.8, 18)
			steamEmitter(rod, 8, 5)
		end
	end
	Build.sign(m, "THE VALVE", CF(SEAL.X + 30, gy + 6.5, SEAL.Z + 4) * ANG(0, -math.pi / 2, 0), V3(14, 2.2, 0.4), Color3.fromRGB(40, 28, 18), CREAM)
	Build.part(m, { name = "ValvePostA", size = V3(0.6, 6.4, 0.6), cf = CF(SEAL.X + 30, gy + 3.2, SEAL.Z - 2), color = IRON, material = Enum.Material.Metal })
	Build.part(m, { name = "ValvePostB", size = V3(0.6, 6.4, 0.6), cf = CF(SEAL.X + 30, gy + 3.2, SEAL.Z + 10), color = IRON, material = Enum.Material.Metal })
end

-- Airships ------------------------------------------------------------------------------------------------------------------------------------

local function airship(parent: Instance, pos: Vector3, yaw: number, seed: number)
	local m = Build.model(parent, "Airship")
	local f = CF(pos) * ANG(0, yaw, 0)
	Build.part(m, { name = "Envelope", size = V3(54, 17, 17), cf = f, color = Color3.fromRGB(214, 190, 150), material = Enum.Material.Fabric, shape = "Ball" })
	for k = -2, 2 do
		local d = 17.6 * math.sqrt(1 - (k * 9 / 27) ^ 2)
		Build.part(m, { name = "Band", size = V3(1.2, d, d), cf = f * CF(k * 9, 0, 0), color = BRASS, material = Enum.Material.Metal, shape = "Cylinder" })
	end
	Build.part(m, { name = "Gondola", size = V3(14, 3.6, 5), cf = f * CF(0, -11.4, 0), color = Color3.fromRGB(110, 70, 48), material = Enum.Material.WoodPlanks })
	for _, dx in { -4, 4 } do
		for _, dz in { -2, 2 } do
			Build.part(m, { name = "Rope", size = V3(0.18, 5, 0.18), cf = f * CF(dx, -7.4, dz), color = Color3.fromRGB(70, 60, 50) })
		end
	end
	for _, rot in { 0, math.pi / 2, math.pi, math.pi * 1.5 } do
		Build.part(m, { name = "Fin", size = V3(7, 7, 0.5), cf = f * CF(-25, 0, 0) * ANG(rot, 0, 0) * CF(0, 4, 0), color = COPPER, material = Enum.Material.Metal, shape = "Wedge" })
	end
	local pm = Build.model(m, "Propeller")
	local pf = f * CF(-9, -11.4, 3.6) * ANG(0, math.pi / 2, 0)
	local axle = Build.part(pm, { name = "Axle", size = V3(0.5, 0.5, 1), cf = pf, color = IRON, material = Enum.Material.Metal })
	pm.PrimaryPart = axle
	for k = 0, 1 do
		Build.part(pm, { name = "Blade", size = V3(7, 0.7, 0.3), cf = pf * ANG(0, 0, k * math.pi / 2), color = BRASS, material = Enum.Material.Metal })
	end
	pm:SetAttribute("SpinSpeed", 9)
	Build.tag(pm, "Spin")
	local lamp = Build.part(m, { name = "ShipLamp", size = V3(1.4, 1.4, 1.4), cf = f * CF(7.4, -11.4, 0), color = GLOW, neon = true, shape = "Ball" })
	Build.light(lamp, GLOW, 1.2, 36)
end

-- Fields, streets, scatter ---------------------------------------------------------------------------------------------------------------------

local function signPost(parent: Instance, text: string, x: number, z: number)
	local gy = groundAt(x, z)
	for _, dx in { -5.5, 5.5 } do
		Build.part(parent, { name = "SignPost", size = V3(0.7, 8, 0.7), cf = CF(x + dx, gy + 4, z), color = IRON, material = Enum.Material.Metal, collide = true })
	end
	Build.sign(parent, text, CF(x, gy + 7, z + 0.2) * ANG(0, math.pi, 0), V3(13, 2.4, 0.5), Color3.fromRGB(40, 28, 18), CREAM)
end

local function crate(parent: Instance, pos: Vector3, size: number, yaw: number)
	Build.part(parent, { name = "Crate", size = V3(size, size, size), cf = CF(pos + V3(0, size / 2, 0)) * ANG(0, yaw, 0), color = Color3.fromRGB(130, 96, 64), material = Enum.Material.WoodPlanks, collide = true })
	Build.part(parent, { name = "CrateBand", size = V3(size * 1.04, size * 0.16, size * 1.04), cf = CF(pos + V3(0, size / 2, 0)) * ANG(0, yaw, 0), color = IRON, material = Enum.Material.Metal })
end

local function streets(parent: Instance): { Vector3 }
	local m = Build.model(parent, "Streets")
	local routes = {
		{ V3(SPAWN.X, 0, SPAWN.Z - 8), GATE, V3(C.X, 0, C.Z + 22), V3(TOWER.X, 0, TOWER.Z + 62) },
		{ V3(C.X, 0, C.Z + 22), V3(YARD.X + 40, 0, YARD.Z + 20), V3(YARD.X + 14, 0, YARD.Z) },
		{ V3(C.X, 0, C.Z + 22), V3(WORKS.X - 40, 0, WORKS.Z + 18), V3(WORKS.X - 14, 0, WORKS.Z) },
	}
	local pts: { Vector3 } = {}
	local lampN = 0
	for _, route in routes do
		for i = 1, #route - 1 do
			local a, b = route[i], route[i + 1]
			local len = (b - a).Magnitude
			local steps = math.max(1, math.floor(len / 8))
			local prev = V3(a.X, groundAt(a.X, a.Z) + 0.25, a.Z)
			for k = 1, steps do
				local p = a:Lerp(b, k / steps)
				local cur = V3(p.X, groundAt(p.X, p.Z) + 0.25, p.Z)
				Road.strip(m, "Street", prev, cur, 8, 0.3, Color3.fromRGB(78, 70, 66), Enum.Material.Cobblestone)
				table.insert(pts, cur)
				lampN += 1
				if lampN % 3 == 0 then
					local side = (cur - prev).Unit:Cross(Vector3.yAxis).Unit * 5.2
					gasLamp(m, cur + side)
				end
				prev = cur
			end
		end
	end
	return pts
end

local function buildScatter(parent: Instance, street: { Vector3 })
	local m = Build.model(parent, "Foundry")
	local avoid: { Flora.Zone } = {
		{ pos = SPAWN, radius = 62 },
		{ pos = SKYPORT, radius = 40 },
		{ pos = GATE, radius = 34 },
		{ pos = YARD, radius = 60 },
		{ pos = WORKS, radius = 46 },
		{ pos = TOWER, radius = 74 },
	}
	for i = 1, #street, 2 do
		table.insert(avoid, { pos = street[i], radius = 10 })
	end
	Flora.scatter({
		center = C, radius = 135, count = 26, seed = 4100, minY = 0.2, maxY = 8, avoid = avoid, spacing = 26,
		make = function(pos, i, rnd)
			building(m, pos, 14 + rnd * 12, 12 + Build.hash(i, 9) * 10, 14 + Build.hash(i, 8) * 22, Build.hash(i, 7) * math.pi * 2, i)
		end,
	})
	-- rooftop-style gears standing in the open, some turning
	Flora.scatter({
		center = C, radius = 135, count = 12, seed = 4200, minY = 0.2, maxY = 8, avoid = avoid, spacing = 22,
		make = function(pos, i, rnd)
			local r = 5 + rnd * 5
			gear(m, pos + V3(0, r * 0.6, 0), ANG(0, rnd * 6, 0), r, 12 + (i % 3) * 2, 1.4, if i % 2 == 0 then BRASS else COPPER, if i % 3 == 0 then (0.3 + rnd * 0.4) * (if i % 2 == 0 then 1 else -1) else nil)
		end,
	})
	-- steam vents, barrels and crates
	Flora.scatter({
		center = C, radius = 135, count = 16, seed = 4300, minY = 0.2, maxY = 8, avoid = avoid, spacing = 16,
		make = function(pos, i, rnd)
			local vent = Build.pillar(m, "Vent", pos + V3(0, -0.3, 0), 3, 1.1, { color = IRON, material = Enum.Material.Metal })
			steamEmitter(vent, 14, 8)
		end,
	})
	Flora.scatter({
		center = C, radius = 135, count = 30, seed = 4400, minY = 0.2, maxY = 8, avoid = avoid, spacing = 9,
		make = function(pos, i, rnd)
			if i % 2 == 0 then
				crate(m, pos, 2 + rnd * 1.6, rnd * 6)
			else
				Build.pillar(m, "Barrel", pos, 1.8, 2.4, { color = Color3.fromRGB(104, 76, 52), material = Enum.Material.Wood, collide = true })
			end
		end,
	})
	-- pipes from the tower out to both work yards and along the street
	pipeRun(m, V3(TOWER.X - 22, 0, TOWER.Z + 8), V3(YARD.X + 30, 0, YARD.Z - 22), 9, 2.4, 1)
	pipeRun(m, V3(TOWER.X + 22, 0, TOWER.Z + 8), V3(WORKS.X - 24, 0, WORKS.Z - 14), 9, 2.4, 2)
	pipeRun(m, V3(YARD.X - 30, 0, YARD.Z - 36), V3(YARD.X + 30, 0, YARD.Z - 40), 7, 1.8, 3)
	pipeRun(m, V3(WORKS.X - 28, 0, WORKS.Z + 30), V3(WORKS.X + 26, 0, WORKS.Z + 30), 7, 1.8, 4)
	pipeRun(m, V3(C.X - 54, 0, C.Z + 38), V3(C.X - 54, 0, C.Z - 26), 8, 2, 5)
	pipeRun(m, V3(C.X + 54, 0, C.Z + 38), V3(C.X + 54, 0, C.Z - 26), 8, 2, 6)
	-- crates, barrels and a bench at each yard
	for k, field in { YARD, WORKS } do
		for i = 1, 8 do
			local a = Build.hash(i + k * 9, 21) * math.pi * 2
			local r = (if k == 1 then 50 else 40) + Build.hash(i + k * 9, 22) * 6
			local x, z = field.X + math.cos(a) * r, field.Z + math.sin(a) * r
			local y = Build.groundY(x, z)
			if y and math.abs(y - 0.6) < 1.5 then
				crate(m, V3(x, y, z), 2 + Build.hash(i, 23) * 1.6, Build.hash(i, 24) * 6)
			end
		end
	end
	-- airships over the roofs
	airship(m, V3(C.X - 70, 105, C.Z - 60), 0.4, 1)
	airship(m, V3(C.X + 88, 124, C.Z + 8), -0.5, 2)
end

function Cogspire.build(folder: Folder, ctx: any)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "CogspireSpawn"
	spawn.Anchored = true
	spawn.Size = V3(12, 1, 12)
	spawn.CFrame = CF(V3(SPAWN.X, 1.1, SPAWN.Z))
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Material = Enum.Material.DiamondPlate
	spawn.Color = Color3.fromRGB(150, 110, 60)
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = folder
	ctx.spawn("Cogspire", spawn)
	Forgeheart.skyport(folder, SKYPORT, "SKYPORT: RETURN", ACCENT, math.rad(200))

	buildGate(folder)
	buildClock(folder)
	buildArena(folder)
	local street = streets(folder)
	local signs = Build.model(folder, "FieldSigns")
	signPost(signs, "BOILER YARD", YARD.X + 8, YARD.Z + 54)
	signPost(signs, "AETHER WORKS", WORKS.X - 6, WORKS.Z + 40)
	buildScatter(folder, street)
end

return Cogspire
