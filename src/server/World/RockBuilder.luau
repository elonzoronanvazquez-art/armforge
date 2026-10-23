--!strict
-- Builds the physical model of a rock from its deterministic chunk layout (shared/Logic/RockGeometry).
-- Each chunk is an anchored, non-colliding part; one invisible collider keeps players from walking through the rock.
-- The server strips chunks as the rock takes damage (RockService); clients render the debris themselves.

local CollectionService = game:GetService("CollectionService")
local AssetService = game:GetService("AssetService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local RockConfig = require(Shared.Config.Rocks)
local Assets = require(Shared.Config.Assets)
local Geometry = require(Shared.Logic.RockGeometry)

local RockBuilder = {}

export type Built = { model: Model, chunks: { [number]: BasePart }, collider: BasePart, light: PointLight? }

RockBuilder.TAG = "ArmRock"

-- AI-generated meshes (Config/Assets.Meshes): low-poly stone chunks for shell/mid layers, a crystal for exposed shards,
-- and one "heart" mesh per rock type for the centre of the core. Every one falls back to a primitive part when missing.
local CHUNK_KEYS = { "RockA", "RockB", "RockC" }
local CORE_KEYS: { [string]: string } = {
	Prism = "CoreCrystalCyan",
	Quartz = "CoreQuartz",
	Amethyst = "CoreAmethyst",
	Heartstone = "CoreCrystalCyan",
	Basalt = "CoreMagma",
	MagmaCore = "CoreMagma",
	Obsidian = "CoreObsidian",
}

local templates: { [string]: MeshPart | boolean } = {}

local function template(key: string): MeshPart?
	local cached = templates[key]
	if cached ~= nil then
		return if cached == false then nil else cached :: MeshPart
	end
	local info = Assets.Meshes[key]
	if not info then
		templates[key] = false
		return nil
	end
	local ok, mesh = pcall(function()
		return AssetService:CreateMeshPartAsync(info.mesh :: any, { CollisionFidelity = Enum.CollisionFidelity.Box })
	end)
	if not (ok and mesh) then
		warn(`[ARMFORGE] rock mesh {key} failed to load; using primitive stand-ins`)
		templates[key] = false
		return nil
	end
	if info.texture then
		mesh.TextureID = info.texture :: any
	end
	mesh.Anchored = true
	mesh.CanCollide = false
	mesh.CanQuery = false
	mesh.CanTouch = false
	templates[key] = mesh
	return mesh
end

-- Loads every rock mesh up front so respawns never hitch on an asset download.
function RockBuilder.preload()
	for _, key in CHUNK_KEYS do
		template(key)
	end
	template("CrystalShard")
	for _, key in CORE_KEYS do
		template(key)
	end
end

-- deterministic tiny colour variation so neighbouring chunks differ
local function vary(color: Color3, index: number, amount: number): Color3
	local n = math.sin(index * 12.9898) * 43758.5453
	local f = (n - math.floor(n)) * 2 - 1
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v * (1 + f * amount), 0, 1))
end

-- Creates the part for one chunk and returns it with a flag saying whether it is an AI mesh (whose thin axis is Y).
-- Meshes whose thin axis is Z (everything else is authored thin-on-Y / tall-on-Y).
local THIN_Z: { [string]: boolean } = { RockB = true }
-- Meshes whose baked texture is dropped so the rock's own colours (and Glass / Neon materials) show instead.
local PLAIN_COLOUR: { [string]: boolean } = { CrystalShard = true, RockA = true, RockB = true, RockC = true }

local function makeChunkPart(chunk: Geometry.Chunk, def: RockConfig.RockDef, isCentreCore: boolean): (BasePart, boolean, string?)
	local meshKey: string? = nil
	if chunk.layer == 3 then
		if isCentreCore then
			meshKey = CORE_KEYS[def.id]
		end
	elseif chunk.shape == "Shard" then
		meshKey = "CrystalShard"
	else
		meshKey = CHUNK_KEYS[chunk.variant]
	end
	local tpl = if meshKey then template(meshKey) else nil
	if tpl then
		local clone = tpl:Clone()
		if meshKey and (PLAIN_COLOUR[meshKey] or (isCentreCore and def.id == "Heartstone")) then
			clone.TextureID = ""
		end
		return clone, true, meshKey
	end
	local part: BasePart
	if chunk.shape == "Wedge" or chunk.shape == "Shard" then
		part = Instance.new("WedgePart")
	elseif chunk.shape == "Ball" then
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Ball
		part = p
	else
		part = Instance.new("Part")
	end
	return part, false, nil
end

function RockBuilder.build(def: RockConfig.RockDef, layout: Geometry.Layout, base: CFrame, id: number, parent: Instance): Built
	local model = Instance.new("Model")
	model.Name = `Rock_{id}`
	model:SetAttribute("RockId", id)
	model:SetAttribute("DefId", def.id)
	model:SetAttribute("Hp", def.maxHp)
	model:SetAttribute("MaxHp", def.maxHp)
	model:SetAttribute("Stage", "INTACT")
	model:SetAttribute("Alive", true)
	model:SetAttribute("Radius", layout.radius)
	model:SetAttribute("Height", layout.height)
	model:SetAttribute("Rare", def.rare)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	local chunks: { [number]: BasePart } = {}
	local glowChunk: BasePart? = nil
	local centreDone = false
	for _, chunk in layout.chunks do
		local isCentre = chunk.layer == 3 and not centreDone
		if chunk.layer == 3 then
			centreDone = true
		end
		local part, isMesh, meshKey = makeChunkPart(chunk, def, isCentre)
		part.Name = `C{chunk.index}`
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = chunk.layer == 1
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		local layerKey = if chunk.layer == 1 then "shell" elseif chunk.layer == 2 then "mid" else "core"
		part.Material = (def.materials :: any)[layerKey]
		local color: Color3 = (def.colors :: any)[layerKey]
		part.Color = vary(color, chunk.index, if chunk.layer == 3 then 0.06 else 0.16)
		if chunk.layer == 2 and def.glowCore then
			-- exposed mineral layer glows faintly so damage reads from a distance
			part.Reflectance = 0.05
		end
		if isMesh and meshKey and THIN_Z[meshKey] and chunk.layer ~= 3 then
			-- thin-on-Z meshes use the same orientation as primitive chunks (Z = thickness along the outward direction)
			part.Size = chunk.size
			part.CFrame = base * CFrame.lookAt(chunk.pos, chunk.pos + chunk.dir) * CFrame.Angles(0, 0, chunk.roll)
			part.Material = (def.materials :: any)[layerKey]
		elseif isMesh then
			-- AI meshes are authored with their thin axis on Y: point Y along the chunk's outward direction
			local up = chunk.dir
			local ref = if math.abs(up.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
			local x = ref:Cross(up).Unit
			local z = x:Cross(up)
			if chunk.layer == 3 then
				local s = layout.radius * 1.5
				part.Size = Vector3.new(s, s * 1.1, s)
				part.CFrame = base * CFrame.new(chunk.pos) * CFrame.Angles(0, chunk.roll, 0)
			else
				part.Size = Vector3.new(chunk.size.X, chunk.size.Z, chunk.size.Y)
				part.CFrame = base * CFrame.fromMatrix(chunk.pos, x, up, z) * CFrame.Angles(0, chunk.roll, 0)
			end
			part.Material = if chunk.layer == 3 then Enum.Material.SmoothPlastic else (def.materials :: any)[layerKey]
		else
			part.Size = chunk.size
			part.CFrame = base * CFrame.lookAt(chunk.pos, chunk.pos + chunk.dir) * CFrame.Angles(0, 0, chunk.roll)
		end
		part.Parent = model
		chunks[chunk.index] = part
		if chunk.layer == 3 and glowChunk == nil then
			glowChunk = part
		end
	end

	-- collision: one cylinder slightly inside the visual shell
	local collider = Instance.new("Part")
	collider.Name = "Collider"
	collider.Shape = Enum.PartType.Cylinder
	collider.Size = Vector3.new(layout.height * 0.9, layout.radius * 1.7, layout.radius * 1.7)
	collider.CFrame = base * CFrame.new(0, layout.height * 0.45, 0) * CFrame.Angles(0, 0, math.pi / 2)
	collider.Anchored = true
	collider.Transparency = 1
	collider.CanCollide = true
	collider.CanTouch = false
	collider.CanQuery = true
	collider.CastShadow = false
	collider.Parent = model
	model.PrimaryPart = collider

	local light: PointLight? = nil
	if def.rare and glowChunk then
		local l = Instance.new("PointLight")
		l.Color = def.colors.glow
		l.Brightness = 1.2
		l.Range = 16
		l.Shadows = false
		l.Parent = glowChunk
		light = l
	end

	CollectionService:AddTag(model, RockBuilder.TAG)
	model.Parent = parent
	return { model = model, chunks = chunks, collider = collider, light = light }
end

-- Low rubble left on the ground during the aftermath. Returns a Model (destroyed by RockService on respawn).
function RockBuilder.rubble(def: RockConfig.RockDef, layout: Geometry.Layout, base: CFrame, id: number, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = `Rubble_{id}`
	local count = 6
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + id
		local r = layout.radius * (0.25 + 0.55 * ((i * 37) % 10) / 10)
		local s = layout.radius * (0.16 + 0.1 * ((i * 53) % 7) / 7)
		local part = Instance.new("Part")
		part.Name = `R{i}`
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Size = Vector3.new(s * 1.6, s, s * 1.3)
		part.Material = if i % 3 == 0 then def.materials.mid else def.materials.shell
		part.Color = if i % 3 == 0 then def.colors.mid else vary(def.colors.shell, i + id, 0.2)
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.CFrame = base * CFrame.new(math.cos(angle) * r, s * 0.35, math.sin(angle) * r) * CFrame.Angles(i * 0.7, i * 1.3, i * 0.4)
		part.Parent = model
	end
	-- a glowing ember of the core colour
	local ember = Instance.new("Part")
	ember.Name = "Ember"
	ember.Anchored = true
	ember.CanCollide = false
	ember.CanTouch = false
	ember.CanQuery = false
	ember.Shape = Enum.PartType.Ball
	ember.Size = Vector3.new(1, 1, 1) * layout.radius * 0.22
	ember.Material = Enum.Material.Neon
	ember.Color = def.colors.glow
	ember.CFrame = base * CFrame.new(0, layout.radius * 0.1, 0)
	ember.Parent = model
	model.Parent = parent
	return model
end

return RockBuilder
