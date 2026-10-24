--!strict
-- Builds the whole world at server start (the Rojo place ships empty; the world is code). Order matters:
-- lighting, sea + island terrain, structures (each island module), rocks, then players may spawn.

local Lighting = game:GetService("Lighting")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local IslandConfig = require(Shared.Config.Islands)
local IslandTerrain = require(script.Parent.IslandTerrain)
local Build = require(script.Parent.Build)
local Forgeheart = require(script.Parent.Islands.Forgeheart)
local Crystalfall = require(script.Parent.Islands.Crystalfall)
local Emberfang = require(script.Parent.Islands.Emberfang)
local Mossveil = require(script.Parent.Islands.Mossveil)
local Dustwake = require(script.Parent.Islands.Dustwake)
local Cogspire = require(script.Parent.Islands.Cogspire)
local Voidreach = require(script.Parent.Islands.Voidreach)

local WorldBuilder = {}

export type Context = {
	root: Folder,
	spawn: (islandId: string, spawn: SpawnLocation) -> (),
}

local SEA_LEVEL = -1.6

local function setupLighting()
	Lighting.ClockTime = 16.2
	Lighting.GeographicLatitude = 28
	Lighting.Brightness = 2.6
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.OutdoorAmbient = Color3.fromRGB(104, 96, 110)
	Lighting.Ambient = Color3.fromRGB(70, 64, 78)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 214, 170)
	Lighting.ExposureCompensation = 0.1
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.35
	for _, child in Lighting:GetChildren() do
		if child:IsA("Atmosphere") or child:IsA("Sky") or child:IsA("BloomEffect") or child:IsA("ColorCorrectionEffect") or child:IsA("SunRaysEffect") or child:IsA("DepthOfFieldEffect") then
			child:Destroy()
		end
	end
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.32
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(255, 196, 150)
	atmosphere.Decay = Color3.fromRGB(150, 110, 120)
	atmosphere.Glare = 0.25
	atmosphere.Haze = 1.4
	atmosphere.Parent = Lighting
	local sky = Instance.new("Sky")
	sky.StarCount = 3000
	sky.SunAngularSize = 14
	sky.CelestialBodiesShown = true
	sky.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.45
	bloom.Size = 28
	bloom.Threshold = 1.05
	bloom.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "Grade"
	cc.Saturation = 0.12
	cc.Contrast = 0.08
	cc.TintColor = Color3.fromRGB(255, 244, 232)
	cc.Parent = Lighting
	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.08
	rays.Spread = 0.6
	rays.Parent = Lighting
end

local function setupTerrain()
	local t = workspace.Terrain
	t:Clear()
	t.WaterColor = Color3.fromRGB(32, 112, 130)
	t.WaterTransparency = 0.82
	t.WaterReflectance = 0.55
	t.WaterWaveSize = 0.18
	t.WaterWaveSpeed = 7
	t:SetMaterialColor(Enum.Material.Slate, Color3.fromRGB(86, 78, 82))
	t:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(112, 84, 62))
	t:SetMaterialColor(Enum.Material.Pavement, Color3.fromRGB(138, 130, 124))
	t:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(98, 88, 86))
	t:SetMaterialColor(Enum.Material.Basalt, Color3.fromRGB(72, 62, 66))
	t:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(216, 186, 130))
	t:SetMaterialColor(Enum.Material.Cobblestone, Color3.fromRGB(112, 98, 88))
	t:SetMaterialColor(Enum.Material.Sandstone, Color3.fromRGB(196, 150, 100))
	t:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(78, 122, 62))
	t:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(62, 106, 56))
	t:SetMaterialColor(Enum.Material.Concrete, Color3.fromRGB(120, 116, 112))
	t:SetMaterialColor(Enum.Material.Glacier, Color3.fromRGB(150, 194, 228))
	t:SetMaterialColor(Enum.Material.Limestone, Color3.fromRGB(166, 168, 180))
	t:SetMaterialColor(Enum.Material.Snow, Color3.fromRGB(232, 238, 248))
	t:SetMaterialColor(Enum.Material.Ice, Color3.fromRGB(176, 218, 240))
	t:SetMaterialColor(Enum.Material.CrackedLava, Color3.fromRGB(255, 96, 40))
	t:SetMaterialColor(Enum.Material.Mud, Color3.fromRGB(70, 56, 54))
end

local function terrainSpec(id: string): IslandTerrain.Spec
	local def = IslandConfig.Defs[id]
	local feats = if id == "Forgeheart" then Forgeheart.features()
		elseif id == "Crystalfall" then Crystalfall.features()
		elseif id == "Emberfang" then Emberfang.features()
		elseif id == "Mossveil" then Mossveil.features()
		elseif id == "Dustwake" then Dustwake.features()
		elseif id == "Cogspire" then Cogspire.features()
		else {}
	local spec: IslandTerrain.Spec = {
		center = def.center,
		radius = def.radius,
		plateau = 0.7,
		plateauH = 0.6,
		seaLevel = SEA_LEVEL,
		floor = -18,
		noiseScale = 70,
		noiseAmp = 2.2,
		coastWobble = 0.1,
		seed = #id * 3.7,
		features = feats,
		ground = Enum.Material.Slate,
		ground2 = Enum.Material.Ground,
		rock = Enum.Material.Rock,
		shore = Enum.Material.Sand,
		deep = Enum.Material.Basalt,
	}
	if id == "Crystalfall" then
		-- the snow mountain: snow with pale limestone crags on the steep faces; tall enough to need extra layers
		spec.ground = Enum.Material.Snow
		spec.ground2 = Enum.Material.Snow
		spec.rock = Enum.Material.Limestone
		spec.shore = Enum.Material.Ice
		spec.deep = Enum.Material.Glacier
		spec.noiseAmp = 2.4
		spec.layers = 32
	elseif id == "Emberfang" then
		spec.ground = Enum.Material.Basalt
		spec.ground2 = Enum.Material.Slate
		spec.rock = Enum.Material.Basalt
		spec.shore = Enum.Material.Mud
		spec.deep = Enum.Material.Basalt
		spec.noiseAmp = 3
		spec.layers = 26
	elseif id == "Mossveil" then
		spec.ground = Enum.Material.Grass
		spec.ground2 = Enum.Material.LeafyGrass
		spec.rock = Enum.Material.Rock
		spec.shore = Enum.Material.Ground
		spec.deep = Enum.Material.Basalt
		spec.noiseScale = 58
		spec.noiseAmp = 3.4
	elseif id == "Cogspire" then
		spec.ground = Enum.Material.Cobblestone
		spec.ground2 = Enum.Material.Pavement
		spec.rock = Enum.Material.Slate
		spec.shore = Enum.Material.Concrete
		spec.deep = Enum.Material.Slate
		spec.noiseScale = 80
		spec.noiseAmp = 1.2
	elseif id == "Dustwake" then
		spec.ground = Enum.Material.Sand
		spec.ground2 = Enum.Material.Sand
		spec.rock = Enum.Material.Sandstone
		spec.shore = Enum.Material.Sand
		spec.deep = Enum.Material.Sandstone
		spec.noiseScale = 90
		spec.noiseAmp = 2.6
	end
	return spec
end

-- Builds everything; yields. `onSpawn` registers SpawnLocations with the player service.
function WorldBuilder.build(onSpawn: (string, SpawnLocation) -> ()): Folder
	local old = workspace:FindFirstChild("ArmforgeWorld")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "ArmforgeWorld"
	root.Parent = workspace

	setupLighting()
	setupTerrain()

	IslandTerrain.fillSea(-1400, 1400, -1500, 1300, SEA_LEVEL)
	task.wait()
	for _, id in { "Forgeheart", "Crystalfall", "Emberfang", "Mossveil", "Dustwake", "Cogspire" } do
		IslandTerrain.build(terrainSpec(id))
	end

	local ctx: Context = { root = root, spawn = onSpawn }
	local forgeFolder = Build.folder(root, "Forgeheart")
	Forgeheart.build(forgeFolder, ctx)
	task.wait()
	Crystalfall.build(Build.folder(root, "Crystalfall"), ctx)
	task.wait()
	Emberfang.build(Build.folder(root, "Emberfang"), ctx)
	task.wait()
	Mossveil.build(Build.folder(root, "Mossveil"), ctx)
	task.wait()
	Dustwake.build(Build.folder(root, "Dustwake"), ctx)
	task.wait()
	Cogspire.build(Build.folder(root, "Cogspire"), ctx)
	task.wait()
	Voidreach.build(Build.folder(root, "Voidreach"), ctx)

	-- a kill plane so nobody falls forever
	local plane = Build.part(root, {
		name = "KillPlane",
		size = Vector3.new(4000, 4, 4000),
		cf = CFrame.new(0, -90, -500),
		transparency = 1,
		collide = false,
	})
	plane.CanTouch = true
	plane.Touched:Connect(function(hit)
		local hum = hit.Parent and hit.Parent:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Health = 0
		end
	end)
	return root
end

return WorldBuilder
