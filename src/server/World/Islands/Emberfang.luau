--!strict
-- EMBERFANG CALDERA: black basalt, glowing cracks, fang-shaped spires around a magma lake.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local IslandConfig = require(Shared.Config.Islands)
local Build = require(script.Parent.Parent.Build)
local IslandTerrain = require(script.Parent.Parent.IslandTerrain)
local Forgeheart = require(script.Parent.Forgeheart)

local Emberfang = {}

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local CENTER = IslandConfig.Defs.Emberfang.center
local ACCENT = IslandConfig.Defs.Emberfang.accent

function Emberfang.features(): { IslandTerrain.Feature }
	local c = CENTER
	return {
		{ kind = "flat", pos = V3(c.X, 0, c.Z + 96), radius = 46, target = 0.6, material = Enum.Material.Basalt },
		{ kind = "flat", pos = V3(c.X, 0, c.Z - 50), radius = 66, target = 0.6, material = Enum.Material.Basalt },
		{ kind = "flat", pos = V3(c.X - 84, 0, c.Z - 96), radius = 52, target = 0.6, material = Enum.Material.Slate },
		-- the magma lake
		{ kind = "pit", pos = V3(c.X + 70, 0, c.Z + 10), radius = 56, height = 5, material = Enum.Material.CrackedLava },
		{ kind = "pit", pos = V3(c.X - 60, 0, c.Z + 40), radius = 24, height = 4, material = Enum.Material.CrackedLava },
		{ kind = "hill", pos = V3(c.X + 130, 0, c.Z - 70), radius = 44, height = 22 },
		{ kind = "ridge", pos = V3(c.X, 0, c.Z - 170), radius = 26, height = 26, angle = 0, length = 150 },
	}
end

local function fang(parent: Instance, pos: Vector3, h: number, w: number, lean: number, yaw: number)
	local m = Build.model(parent, "Fang")
	Build.part(m, { name = "FangBody", size = V3(w, h, w), cf = CF(pos + V3(0, h / 2, 0)) * ANG(lean, yaw, 0), color = Color3.fromRGB(28, 26, 32), material = Enum.Material.Basalt, shape = "Wedge", collide = true })
	Build.part(m, { name = "FangSeam", size = V3(w * 0.16, h * 0.8, w * 0.4), cf = CF(pos + V3(0, h * 0.42, 0)) * ANG(lean, yaw, 0) * CF(w * 0.3, 0, 0), color = Color3.fromRGB(255, 96, 40), neon = true, shape = "Wedge" })
	return m
end

function Emberfang.build(folder: Folder, ctx: any)
	local c = CENTER
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "EmberfangSpawn"
	spawn.Anchored = true
	spawn.Size = V3(12, 1, 12)
	spawn.CFrame = CF(V3(c.X, 1.1, c.Z + 96))
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Material = Enum.Material.Basalt
	spawn.Color = Color3.fromRGB(46, 40, 48)
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = folder
	ctx.spawn("Emberfang", spawn)
	Forgeheart.skyport(folder, V3(c.X - 38, 0, c.Z + 100), "SKYPORT: RETURN", ACCENT, math.rad(200))

	-- entrance gate of two giant fangs
	local gate = Build.model(folder, "FangGate")
	local gp = V3(c.X, 0, c.Z + 30)
	fang(gate, gp + V3(-16, 0, 0), 42, 14, -0.12, 0)
	fang(gate, gp + V3(16, 0, 0), 46, 14, 0.12, math.pi)
	Build.sign(gate, "EMBERFANG CALDERA", CF(gp + V3(0, 12, 6)) * ANG(0, math.pi, 0), V3(22, 2.6, 0.5), Color3.fromRGB(30, 20, 20), Color3.fromRGB(255, 190, 120))
	Build.part(gate, { name = "SignPostL", size = V3(0.8, 12, 0.8), cf = CF(gp + V3(-9, 6, 6)), color = Color3.fromRGB(50, 40, 44), material = Enum.Material.Metal })
	Build.part(gate, { name = "SignPostR", size = V3(0.8, 12, 0.8), cf = CF(gp + V3(9, 6, 6)), color = Color3.fromRGB(50, 40, 44), material = Enum.Material.Metal })

	-- ring of fangs around the caldera rim + glowing vents
	local rim = Build.model(folder, "Rim")
	for i = 1, 22 do
		local a = Build.hash(i, 1) * math.pi * 2
		local r = 70 + Build.hash(i, 2) * 110
		local x, z = c.X + math.cos(a) * r, c.Z + math.sin(a) * r
		local y = Build.groundY(x, z)
		if y and y > 0 then
			fang(rim, V3(x, y - 1, z), 10 + Build.hash(i, 3) * 26, 4 + Build.hash(i, 4) * 6, (Build.hash(i, 5) - 0.5) * 0.4, Build.hash(i, 6) * 6)
		end
	end
	for i = 1, 16 do
		local a = Build.hash(i, 11) * math.pi * 2
		local r = 40 + Build.hash(i, 12) * 140
		local x, z = c.X + math.cos(a) * r, c.Z + math.sin(a) * r
		local y = Build.groundY(x, z)
		if y and y > 0 then
			local vent = Build.pillar(rim, "Vent", V3(x, y - 0.4, z), 3 + Build.hash(i, 13) * 2, 1.2, { color = Color3.fromRGB(255, 110, 40), neon = true })
			Build.emitter(vent, {
				Rate = 10,
				Lifetime = NumberRange.new(1.5, 3),
				Speed = NumberRange.new(3, 8),
				SpreadAngle = Vector2.new(20, 20),
				Color = ColorSequence.new(Color3.fromRGB(255, 160, 60)),
				LightEmission = 1,
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) }),
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
				Acceleration = Vector3.new(0, 6, 0),
				EmissionDirection = Enum.NormalId.Top,
			})
			if i % 4 == 0 then
				Build.light(vent, Color3.fromRGB(255, 120, 50), 1.2, 22)
			end
		end
	end
end

return Emberfang
