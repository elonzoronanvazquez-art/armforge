--!strict
-- THE ATLANTIC SEA (a zone, Config/Zones): a coral atoll far out in open water that a fishing trip can pull you to. Sandy beaches round a
-- lagoon, palms, coral, a half-sunk wreck and a striped lighthouse whose prompt sails you home. Two rock fields (Reef Shallows, Pearl Bank)
-- pay +25% coins and XP. There is no way here except the tide.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local ZoneConfig = require(Shared.Config.Zones)
local Build = require(script.Parent.Parent.Build)
local Flora = require(script.Parent.Parent.Flora)
local IslandTerrain = require(script.Parent.Parent.IslandTerrain)

local AtlanticSea = {}

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles

local DEF = ZoneConfig.Defs.AtlanticSea
local C = DEF.center
local ARRIVAL = V3(DEF.arrival.X, 0, DEF.arrival.Z)
local REEF = DEF.fields[1].center
local PEARL = DEF.fields[2].center
local LAGOON = V3(C.X - 70, 0, C.Z + 30)

local WHITE = Color3.fromRGB(240, 240, 236)
local RED = Color3.fromRGB(204, 70, 60)
local WOOD = Color3.fromRGB(110, 80, 54)

function AtlanticSea.features(): { IslandTerrain.Feature }
	return {
		{ kind = "hill", pos = V3(C.X + 62, 0, C.Z + 8), radius = 30, height = 5 },
		{ kind = "hill", pos = V3(C.X - 10, 0, C.Z + 60), radius = 24, height = 4 },
		{ kind = "pit", pos = LAGOON, radius = 30, height = 7, material = Enum.Material.Sand },
		{ kind = "flat", pos = ARRIVAL, radius = 30, target = 0.6, material = Enum.Material.Sand },
		{ kind = "flat", pos = REEF, radius = 40, target = 0.6, material = Enum.Material.Sand },
		{ kind = "flat", pos = PEARL, radius = 36, target = 0.6, material = Enum.Material.Sand },
	}
end

local function groundAt(x: number, z: number): number
	return Build.groundY(x, z) or 0.6
end

-- A branching coral head.
local function coral(parent: Instance, pos: Vector3, seed: number, color: Color3)
	local m = Build.model(parent, "Coral")
	local n = 4 + math.floor(Build.hash(seed, 1) * 4)
	for i = 1, n do
		local a = Build.hash(seed, i) * math.pi * 2
		local h = 2 + Build.hash(seed, i + 10) * 3.5
		local lean = (Build.hash(seed, i + 20) - 0.5) * 0.8
		Build.part(m, { name = "CoralArm", size = V3(h, 0.9, 0.9), cf = CF(pos + V3(math.cos(a) * 0.9, h / 2 - 0.2, math.sin(a) * 0.9)) * ANG(0, a, lean + math.pi / 2), color = color:Lerp(Color3.new(1, 1, 1), Build.hash(seed, i + 30) * 0.3), material = Enum.Material.Marble, shape = "Cylinder" })
		Build.part(m, { name = "CoralTip", size = V3(1.4, 1.4, 1.4), cf = CF(pos + V3(math.cos(a) * (0.9 + math.sin(lean) * h / 2), h - 0.2, math.sin(a) * (0.9 + math.sin(lean) * h / 2))), color = color, material = Enum.Material.Marble, shape = "Ball" })
	end
end

local function buildLighthouse(parent: Instance)
	local m = Build.model(parent, "Lighthouse")
	local pos = V3(ARRIVAL.X + 18, groundAt(ARRIVAL.X + 18, ARRIVAL.Z - 6), ARRIVAL.Z - 6)
	for k = 0, 5 do
		Build.pillar(m, "Tower", pos + V3(0, k * 7, 0), 9 - k * 0.8, 7.2, { color = if k % 2 == 0 then WHITE else RED, material = Enum.Material.Concrete, collide = true })
	end
	Build.pillar(m, "Gallery", pos + V3(0, 42, 0), 8.6, 0.8, { color = Color3.fromRGB(50, 52, 60), material = Enum.Material.Metal })
	local lamp = Build.part(m, { name = "Lamp", size = V3(4, 4, 4), cf = CF(pos + V3(0, 45, 0)), color = Color3.fromRGB(255, 240, 180), neon = true, shape = "Ball" })
	Build.light(lamp, Color3.fromRGB(255, 236, 170), 2.4, 90)
	Build.pillar(m, "Roof", pos + V3(0, 47.2, 0), 5.4, 2.4, { color = RED, material = Enum.Material.Metal })
	-- the door and the prompt that sails you home
	local door = Build.part(m, { name = "SailHome", size = V3(5, 7, 2), cf = CF(pos + V3(0, 3.6, -4.6)), color = Color3.fromRGB(70, 50, 36), material = Enum.Material.Wood, collide = true })
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Sail home"
	prompt.ObjectText = "The Atlantic Lighthouse"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = door
	Build.tag(door, "ZoneExit")
	Build.sign(m, "SAIL HOME", CF(pos + V3(0, 9.2, -5.8)) * ANG(0, math.pi, 0), V3(10, 1.8, 0.4), Color3.fromRGB(28, 40, 52), Color3.fromRGB(200, 240, 250))
end

local function buildWreck(parent: Instance)
	local m = Build.model(parent, "Wreck")
	local p = V3(C.X + 40, 0, C.Z - 60)
	local y = groundAt(p.X, p.Z)
	Build.part(m, { name = "Hull", size = V3(8, 5, 22), cf = CF(p.X, y + 1, p.Z) * ANG(0.12, 0.5, 0.35), color = Color3.fromRGB(96, 70, 48), material = Enum.Material.WoodPlanks, collide = true })
	Build.part(m, { name = "Bow", size = V3(8, 5, 8), cf = CF(p.X + 5, y + 2.4, p.Z - 13) * ANG(0.12, 0.5 + math.pi, 0.35), color = Color3.fromRGB(96, 70, 48), material = Enum.Material.WoodPlanks, shape = "Wedge" })
	Build.pillar(m, "Mast", V3(p.X - 2, y, p.Z + 3), 1, 16, { color = WOOD, material = Enum.Material.Wood })
	Build.part(m, { name = "Sail", size = V3(0.3, 9, 6), cf = CF(p.X - 2, y + 11, p.Z + 3) * ANG(0, 0.4, 0.2), color = Color3.fromRGB(220, 210, 190), material = Enum.Material.Fabric })
	-- the sailors' chest
	Build.part(m, { name = "Chest", size = V3(3, 2, 2), cf = CF(p.X + 6, y + 1, p.Z + 5), color = Color3.fromRGB(122, 84, 46), material = Enum.Material.Wood, collide = true })
	Build.part(m, { name = "ChestBand", size = V3(3.2, 0.4, 2.2), cf = CF(p.X + 6, y + 1.5, p.Z + 5), color = Color3.fromRGB(214, 170, 60), material = Enum.Material.Metal })
end

function AtlanticSea.build(folder: Folder, _ctx: any)
	buildLighthouse(folder)
	buildWreck(folder)
	local m = Build.model(folder, "Reef")
	local avoid: { Flora.Zone } = {
		{ pos = ARRIVAL, radius = 34 },
		{ pos = REEF, radius = 40 },
		{ pos = PEARL, radius = 34 },
		{ pos = V3(C.X + 40, 0, C.Z - 60), radius = 18 },
	}
	Flora.scatter({
		center = C, radius = 100, count = 34, seed = 5100, minY = 0.2, maxY = 8, avoid = avoid, spacing = 12,
		make = function(pos, i, rnd)
			Flora.palm(m, pos, 10 + rnd * 6, i, Color3.fromRGB(80, 140, 70))
		end,
	})
	local pal = { Color3.fromRGB(238, 110, 120), Color3.fromRGB(250, 170, 90), Color3.fromRGB(190, 120, 220), Color3.fromRGB(110, 210, 200) }
	Flora.scatter({
		center = C, radius = 112, count = 60, seed = 5200, minY = -1.4, maxY = 3, avoid = avoid, spacing = 7, tries = 20,
		make = function(pos, i)
			coral(m, pos, i, pal[1 + i % #pal])
		end,
	})
	Flora.scatter({
		center = C, radius = 110, count = 30, seed = 5300, minY = 0.2, maxY = 6, avoid = avoid, spacing = 6,
		make = function(pos, i, rnd)
			Flora.tuft(m, pos, 1.6 + rnd * 1.4, i, Color3.fromRGB(150, 180, 90))
		end,
	})
	-- glowing buoys marking the way out of the lagoon
	for i = 0, 7 do
		local a = (i / 8) * math.pi * 2
		local x, z = LAGOON.X + math.cos(a) * 26, LAGOON.Z + math.sin(a) * 26
		local buoy = Build.part(m, { name = "Buoy", size = V3(1.6, 2.4, 1.6), cf = CF(x, -1, z), color = if i % 2 == 0 then RED else WHITE, material = Enum.Material.Metal, shape = "Ball" })
		if i % 2 == 0 then
			Build.light(buoy, Color3.fromRGB(255, 150, 120), 0.8, 16)
		end
	end
	-- field signs
	local fieldSigns: { { name: string, at: Vector3 } } = { { name = "REEF SHALLOWS", at = REEF }, { name = "PEARL BANK", at = PEARL } }
	for _, spec in fieldSigns do
		local name, at = spec.name, spec.at
		local y = groundAt(at.X, at.Z + 36)
		for _, dx in { -5, 5 } do
			Build.part(m, { name = "SignPost", size = V3(0.6, 7, 0.6), cf = CF(at.X + dx, y + 3.5, at.Z + 36), color = WOOD, material = Enum.Material.Wood })
		end
		Build.sign(m, name, CF(at.X, y + 6.5, at.Z + 36) * ANG(0, math.pi, 0), V3(12, 2.2, 0.4), Color3.fromRGB(28, 40, 52), Color3.fromRGB(200, 240, 250))
	end
	Build.sign(m, "THE ATLANTIC SEA  ·  +25% COINS & XP", CF(ARRIVAL.X - 14, groundAt(ARRIVAL.X - 14, ARRIVAL.Z - 12) + 9, ARRIVAL.Z - 12) * ANG(0, math.pi, 0), V3(24, 2.6, 0.4), Color3.fromRGB(28, 40, 52), Color3.fromRGB(150, 240, 250))
end

return AtlanticSea
