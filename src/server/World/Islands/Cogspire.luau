--!strict
-- COGSPIRE FOUNDRY: the steampunk island is not playable yet. A brass platform with turning gears, smokestacks and a lit sign in the
-- sea teases it. The island is data-complete (Config/Islands.Cogspire, comingSoon = true), so enabling it later only needs rocks,
-- creatures, a guardian, terrain and a real builder here (docs/NEXT.md).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local IslandConfig = require(Shared.Config.Islands)
local Build = require(script.Parent.Parent.Build)

local Cogspire = {}

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles

local BRASS = Color3.fromRGB(196, 146, 66)
local DARK_BRASS = Color3.fromRGB(110, 78, 40)
local COPPER = Color3.fromRGB(176, 98, 62)

function Cogspire.build(folder: Folder, _ctx: any)
	local def = IslandConfig.Defs.Cogspire
	local c = def.center
	local base = V3(c.X, -1.4, c.Z)
	Build.disc(folder, "Platform", base, 90, 2, { color = DARK_BRASS, material = Enum.Material.DiamondPlate, collide = true })
	Build.disc(folder, "PlatformRim", base + V3(0, 2.1, 0), 86, 0.4, { color = BRASS, material = Enum.Material.Metal })
	-- gears: toothed discs standing on the platform
	for i = 0, 2 do
		local a = (i / 3) * math.pi * 2
		local gp = base + V3(math.cos(a) * 24, 14 + i * 3, math.sin(a) * 24)
		local gear = Build.model(folder, "Gear")
		Build.part(gear, { name = "Hub", size = V3(2, 20, 20), cf = CF(gp) * ANG(0, a, 0), color = BRASS, material = Enum.Material.Metal, shape = "Cylinder" })
		for t = 0, 11 do
			local ta = (t / 12) * math.pi * 2
			Build.part(gear, { name = "Tooth", size = V3(2, 4, 3), cf = CF(gp) * ANG(0, a, 0) * ANG(ta, 0, 0) * CF(0, 11, 0), color = DARK_BRASS, material = Enum.Material.Metal })
		end
	end
	-- smokestacks
	for _, dx in { -34, 34 } do
		local stack = Build.pillar(folder, "Smokestack", base + V3(dx, 2, -18), 8, 46, { color = COPPER, material = Enum.Material.Metal })
		Build.pillar(folder, "StackBand", base + V3(dx, 40, -18), 8.8, 1.4, { color = BRASS, material = Enum.Material.Metal })
		Build.emitter(stack, {
			Rate = 7,
			Lifetime = NumberRange.new(5, 8),
			Speed = NumberRange.new(4, 8),
			Color = ColorSequence.new(Color3.fromRGB(210, 206, 200)),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 18) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) }),
			Acceleration = Vector3.new(2, 1, 0),
		})
	end
	local glow = Build.part(folder, { name = "FurnaceGlow", size = V3(10, 8, 1), cf = CF(base + V3(0, 7, 28)), color = Color3.fromRGB(255, 170, 70), neon = true })
	Build.light(glow, Color3.fromRGB(255, 170, 70), 1.4, 50)
	Build.sign(folder, "COGSPIRE FOUNDRY  ·  COMING SOON", CF(base + V3(0, 12, 36)) * ANG(0, math.pi, 0), V3(30, 3, 0.6), Color3.fromRGB(40, 28, 18), Color3.fromRGB(255, 214, 140))
end

return Cogspire
