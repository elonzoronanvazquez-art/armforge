--!strict
-- VOIDREACH: not yet playable. A dark platform and a violet beam far out in the sea tease the next island.
-- The island is data-complete (Config/Islands.Voidreach, comingSoon = true), so enabling it later only needs rocks,
-- terrain and a builder here.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local IslandConfig = require(Shared.Config.Islands)
local Build = require(script.Parent.Parent.Build)

local Voidreach = {}

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles

function Voidreach.build(folder: Folder, _ctx: any)
	local c = IslandConfig.Defs.Voidreach.center
	local base = V3(c.X, -1.4, c.Z)
	Build.disc(folder, "Platform", base, 70, 2, { color = Color3.fromRGB(20, 16, 30), material = Enum.Material.Glass, collide = true })
	Build.disc(folder, "PlatformRim", base + V3(0, 2.1, 0), 66, 0.3, { color = Color3.fromRGB(190, 120, 255), neon = true })
	local beam = Build.pillar(folder, "VoidBeam", base + V3(0, 2, 0), 10, 260, { color = Color3.fromRGB(160, 90, 255), neon = true, transparency = 0.6 })
	Build.light(beam, Color3.fromRGB(180, 110, 255), 1.5, 60)
	for i = 0, 7 do
		local a = (i / 8) * math.pi * 2
		Build.part(folder, {
			name = "OrbitShard",
			size = V3(3, 9, 3),
			cf = CF(base + V3(math.cos(a) * 24, 14 + (i % 3) * 6, math.sin(a) * 24)) * ANG(0.3, a, 0.2),
			color = Color3.fromRGB(110, 60, 190),
			neon = true,
			shape = "Wedge",
		})
	end
	Build.sign(folder, "VOIDREACH  ·  COMING SOON", CF(base + V3(0, 8, 36)) * ANG(0, math.pi, 0), V3(24, 3, 0.6), Color3.fromRGB(16, 12, 26), Color3.fromRGB(210, 160, 255))
end

return Voidreach
