--!strict
-- Builds the physical model of a rock from its deterministic chunk layout (shared/Logic/RockGeometry).
-- Each chunk is an anchored, non-colliding part; one invisible collider keeps players from walking through the rock.
-- The server strips chunks as the rock takes damage (RockService); clients render the debris themselves.

local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local RockConfig = require(Shared.Config.Rocks)
local Geometry = require(Shared.Logic.RockGeometry)

local RockBuilder = {}

export type Built = { model: Model, chunks: { [number]: BasePart }, collider: BasePart, light: PointLight? }

RockBuilder.TAG = "ArmRock"

-- deterministic tiny colour variation so neighbouring chunks differ
local function vary(color: Color3, index: number, amount: number): Color3
	local n = math.sin(index * 12.9898) * 43758.5453
	local f = (n - math.floor(n)) * 2 - 1
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v * (1 + f * amount), 0, 1))
end

local function makeChunkPart(chunk: Geometry.Chunk): BasePart
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
	return part
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
	for _, chunk in layout.chunks do
		local part = makeChunkPart(chunk)
		part.Name = `C{chunk.index}`
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = chunk.layer == 1
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Size = chunk.size
		local layerKey = if chunk.layer == 1 then "shell" elseif chunk.layer == 2 then "mid" else "core"
		part.Material = (def.materials :: any)[layerKey]
		local color: Color3 = (def.colors :: any)[layerKey]
		part.Color = vary(color, chunk.index, if chunk.layer == 3 then 0.06 else 0.16)
		if chunk.layer == 2 and def.glowCore then
			-- exposed mineral layer glows faintly so damage reads from a distance
			part.Reflectance = 0.05
		end
		part.CFrame = base * CFrame.lookAt(chunk.pos, chunk.pos + chunk.dir) * CFrame.Angles(0, 0, chunk.roll)
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
