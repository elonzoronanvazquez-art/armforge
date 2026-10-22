--!strict
-- CRYSTALFALL ATOLL: frosted marble ground, giant singing crystals, an arch you walk through to reach the fields.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local IslandConfig = require(Shared.Config.Islands)
local Build = require(script.Parent.Parent.Build)
local IslandTerrain = require(script.Parent.Parent.IslandTerrain)
local Forgeheart = require(script.Parent.Forgeheart)

local Crystalfall = {}

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local CENTER = IslandConfig.Defs.Crystalfall.center
local ACCENT = IslandConfig.Defs.Crystalfall.accent

function Crystalfall.features(): { IslandTerrain.Feature }
	local c = CENTER
	return {
		{ kind = "flat", pos = V3(c.X, 0, c.Z + 96), radius = 46, target = 0.6, material = Enum.Material.Limestone },
		{ kind = "flat", pos = V3(c.X, 0, c.Z - 50), radius = 66, target = 0.6, material = Enum.Material.Snow },
		{ kind = "flat", pos = V3(c.X + 84, 0, c.Z - 96), radius = 52, target = 0.6, material = Enum.Material.Limestone },
		{ kind = "hill", pos = V3(c.X - 90, 0, c.Z - 20), radius = 40, height = 14 },
		{ kind = "hill", pos = V3(c.X + 120, 0, c.Z + 30), radius = 34, height = 10 },
		{ kind = "ridge", pos = V3(c.X, 0, c.Z - 168), radius = 24, height = 20, angle = 0, length = 140 },
	}
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

function Crystalfall.build(folder: Folder, ctx: any)
	local c = CENTER
	-- arrival pad and return Skyport
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "CrystalfallSpawn"
	spawn.Anchored = true
	spawn.Size = V3(12, 1, 12)
	spawn.CFrame = CF(V3(c.X, 1.1, c.Z + 96))
	spawn.Neutral = true
	spawn.Enabled = true
	spawn.Duration = 0
	spawn.Material = Enum.Material.Glass
	spawn.Color = Color3.fromRGB(120, 180, 230)
	spawn.Transparency = 0.2
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = folder
	ctx.spawn("Crystalfall", spawn)
	Forgeheart.skyport(folder, V3(c.X + 38, 0, c.Z + 100), "SKYPORT: RETURN", ACCENT, math.rad(160))

	-- the Singing Arch: two crystal banks leaning together over the path to the fields
	local arch = Build.model(folder, "SingingArch")
	local archPos = V3(c.X, 0, c.Z + 20)
	for side = -1, 1, 2 do
		for i = 1, 6 do
			local h = 22 + i * 2.4
			local off = side * (13 + i * 0.5)
			local part = Build.part(arch, {
				name = "ArchCrystal",
				size = V3(4.4 - i * 0.3, h, 4.4 - i * 0.3),
				cf = CF(archPos + V3(off, h / 2 - 1, (i - 3.5) * 2.4)) * ANG(0, side * i * 0.3, -side * 0.22),
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
	local arcTop = Build.part(arch, { name = "ArchCap", size = V3(34, 3, 5), cf = CF(archPos + V3(0, 34, 0)), color = ACCENT, neon = true, transparency = 0.35 })
	Build.light(arcTop, ACCENT, 1.4, 60)
	Build.sign(arch, "CRYSTALFALL ATOLL", CF(archPos + V3(0, 14, 7)) * ANG(0, math.pi, 0), V3(22, 2.6, 0.5), Color3.fromRGB(28, 34, 52), Color3.fromRGB(200, 235, 255))
	Build.part(arch, { name = "SignPostL", size = V3(0.8, 14, 0.8), cf = CF(archPos + V3(-10, 7, 7)), color = Color3.fromRGB(90, 100, 130), material = Enum.Material.Metal })
	Build.part(arch, { name = "SignPostR", size = V3(0.8, 14, 0.8), cf = CF(archPos + V3(10, 7, 7)), color = Color3.fromRGB(90, 100, 130), material = Enum.Material.Metal })

	-- scattered crystal clusters and floating shards
	local deco = Build.model(folder, "Crystals")
	for i = 1, 26 do
		local a = Build.hash(i, 1) * math.pi * 2
		local r = 40 + Build.hash(i, 2) * 130
		local x, z = c.X + math.cos(a) * r, c.Z + math.sin(a) * r
		local y = Build.groundY(x, z)
		if y and y > -0.4 then
			local pal = { Color3.fromRGB(130, 200, 255), Color3.fromRGB(200, 150, 255), Color3.fromRGB(150, 255, 235) }
			crystalCluster(deco, V3(x, y, z), 0.7 + Build.hash(i, 3) * 1.2, i, pal[(i % 3) + 1])
		end
	end
	for i = 1, 14 do
		local a = Build.hash(i, 5) * math.pi * 2
		local r = 30 + Build.hash(i, 6) * 120
		local x, z = c.X + math.cos(a) * r, c.Z + math.sin(a) * r
		Build.part(deco, {
			name = "FloatingShard",
			size = V3(1.4, 3.6, 1.4),
			cf = CF(x, 16 + Build.hash(i, 7) * 18, z) * ANG(Build.hash(i, 8), Build.hash(i, 9) * 6, 0.4),
			color = Color3.fromRGB(150, 220, 255),
			neon = true,
			shape = "Wedge",
		})
	end
end

return Crystalfall
