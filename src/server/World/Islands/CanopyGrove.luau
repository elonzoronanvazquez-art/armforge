--!strict
-- THE CANOPY GROVE (a zone, Config/Zones): a secret platform of jade and blossoms floating high above Mossveil. A rare vine swing (2%) flings you
-- up here. It holds the Rootmother's gift (a repeatable chest) and a rope that lowers you back to the jungle.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local ZoneConfig = require(Shared.Config.Zones)
local Build = require(script.Parent.Parent.Build)
local Flora = require(script.Parent.Parent.Flora)

local CanopyGrove = {}

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles

local DEF = ZoneConfig.Defs.CanopyGrove
local C = DEF.center
local FLOOR = DEF.arrival.Y - 3.2 -- the platform's top surface
local MOSS = Color3.fromRGB(72, 132, 64)
local JADE = Color3.fromRGB(110, 230, 160)
local BARK = Color3.fromRGB(88, 66, 48)
local LEAVES = { Color3.fromRGB(52, 108, 56), Color3.fromRGB(66, 124, 60), Color3.fromRGB(86, 140, 64) }

local function prompt(part: BasePart, action: string, object: string, hold: number)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = hold
	p.MaxActivationDistance = 14
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.Parent = part
end

function CanopyGrove.build(folder: Folder, _ctx: any)
	local m = Build.model(folder, "CanopyGrove")
	-- the floating platform: a grassy disc on a cone of rock, with roots and vines trailing under it
	Build.disc(m, "Platform", V3(C.X, FLOOR - 1.6, C.Z), DEF.radius * 2, 1.6, { color = MOSS, material = Enum.Material.Grass, collide = true })
	Build.disc(m, "JadeRing", V3(C.X, FLOOR + 0.05, C.Z), DEF.radius * 2 - 3, 0.2, { color = JADE, neon = true, transparency = 0.3 })
	Build.disc(m, "Lawn", V3(C.X, FLOOR + 0.1, C.Z), DEF.radius * 2 - 4, 0.2, { color = MOSS:Lerp(Color3.new(1, 1, 1), 0.08), material = Enum.Material.Grass, collide = true })
	for k = 1, 5 do
		Build.part(m, { name = "Underside", size = V3(DEF.radius * 2 - k * 9, 4, DEF.radius * 2 - k * 9), cf = CF(C.X, FLOOR - 3.6 - k * 3.6, C.Z), color = Color3.fromRGB(96, 88, 80), material = Enum.Material.Rock, shape = "Ball" })
	end
	for i = 0, 11 do
		local a = (i / 12) * math.pi * 2
		Flora.vine(m, V3(C.X + math.cos(a) * (DEF.radius - 2), FLOOR - 2, C.Z + math.sin(a) * (DEF.radius - 2)), 16 + Build.hash(i, 3) * 20, i, Color3.fromRGB(58, 104, 54))
	end
	-- a ring of low blossoming bushes along the rim keeps people on the platform
	for i = 0, 23 do
		local a = (i / 24) * math.pi * 2
		Flora.bush(m, V3(C.X + math.cos(a) * (DEF.radius - 2.2), FLOOR, C.Z + math.sin(a) * (DEF.radius - 2.2)), 3, i, LEAVES, if i % 3 == 0 then Color3.fromRGB(255, 160, 200) else nil)
	end
	-- four old trees
	for i = 0, 3 do
		local a = (i / 4) * math.pi * 2 + 0.6
		Flora.jungleTree(m, V3(C.X + math.cos(a) * 22, FLOOR, C.Z + math.sin(a) * 22), 26, 8000 + i, { trunk = BARK, leaves = LEAVES }, true)
	end
	-- the gift: a carved chest on a stump of jade, under a ring of light
	local gx, gz = C.X, C.Z - 4
	Build.pillar(m, "GiftStump", V3(gx, FLOOR, gz), 7, 2.4, { color = Color3.fromRGB(70, 130, 96), material = Enum.Material.Marble, collide = true })
	local chest = Build.part(m, { name = "GiftChest", size = V3(4.4, 2.6, 3), cf = CF(gx, FLOOR + 3.7, gz), color = Color3.fromRGB(122, 84, 46), material = Enum.Material.Wood, collide = true })
	Build.part(m, { name = "GiftLid", size = V3(4.6, 1.2, 3.2), cf = CF(gx, FLOOR + 5.4, gz), color = Color3.fromRGB(150, 104, 56), material = Enum.Material.Wood })
	Build.part(m, { name = "GiftBand", size = V3(4.8, 0.5, 3.4), cf = CF(gx, FLOOR + 4.9, gz), color = Color3.fromRGB(214, 170, 60), material = Enum.Material.Metal })
	local glow = Build.part(m, { name = "GiftGlow", size = V3(2, 2, 2), cf = CF(gx, FLOOR + 6.8, gz), color = JADE, neon = true, shape = "Ball" })
	Build.light(glow, JADE, 1.6, 40)
	prompt(chest, "Open the gift", "The Rootmother's Gift", 0)
	Build.tag(chest, "GroveGift")
	Build.sign(m, "THE CANOPY GROVE  ·  YOU FOUND IT", CF(gx, FLOOR + 10, gz + 8) * ANG(0, math.pi, 0), V3(22, 2.4, 0.4), Color3.fromRGB(26, 44, 30), Color3.fromRGB(190, 255, 180))
	-- the way down: a rope hanging over the edge
	local rx, rz = C.X + 26, C.Z
	local post = Build.part(m, { name = "RopePost", size = V3(1, 7, 1), cf = CF(rx, FLOOR + 3.5, rz), color = BARK, material = Enum.Material.Wood, collide = true })
	Build.part(m, { name = "RopeBeam", size = V3(1, 0.8, 5), cf = CF(rx, FLOOR + 7, rz), color = BARK, material = Enum.Material.Wood })
	Build.part(m, { name = "RopeLine", size = V3(0.4, 14, 0.4), cf = CF(rx + 1.5, FLOOR - 3.2, rz), color = Color3.fromRGB(230, 196, 120), material = Enum.Material.Fabric })
	prompt(post, "Climb down", "The Rope to Mossveil", 0.3)
	Build.tag(post, "GroveExit")
	Build.sign(m, "ROPE DOWN", CF(rx, FLOOR + 9, rz - 4) * ANG(0, 0, 0), V3(8, 1.8, 0.4), Color3.fromRGB(26, 44, 30), Color3.fromRGB(190, 255, 180))
	-- fireflies and falling petals for atmosphere
	local box = Build.part(m, { name = "Fireflies", size = V3(50, 12, 50), cf = CF(C.X, FLOOR + 7, C.Z), transparency = 1 })
	Build.emitter(box, {
		Rate = 6,
		Lifetime = NumberRange.new(4, 7),
		Speed = NumberRange.new(0.4, 1.4),
		SpreadAngle = Vector2.new(180, 180),
		Color = ColorSequence.new(Color3.fromRGB(210, 255, 150)),
		LightEmission = 1,
		Size = NumberSequence.new(0.4),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0), NumberSequenceKeypoint.new(0.8, 0), NumberSequenceKeypoint.new(1, 1) }),
	})
end

return CanopyGrove
