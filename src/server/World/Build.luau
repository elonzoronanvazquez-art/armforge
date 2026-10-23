--!strict
-- Small helpers for assembling the world from primitives. Everything built here is anchored; decoration does not
-- collide unless asked to, so players never snag on lamps, pipes or railings.

local CollectionService = game:GetService("CollectionService")
local AssetService = game:GetService("AssetService")

local Assets = require(game:GetService("ReplicatedStorage"):WaitForChild("Armforge").Config.Assets)

local Build = {}

export type PartOpts = {
	name: string?,
	size: Vector3?,
	cf: CFrame?,
	color: Color3?,
	material: Enum.Material?,
	shape: string?, -- Block | Ball | Cylinder | Wedge | Corner
	transparency: number?,
	reflectance: number?,
	collide: boolean?,
	neon: boolean?,
	castShadow: boolean?,
}

function Build.part(parent: Instance, o: PartOpts): BasePart
	local part: BasePart
	local shape = o.shape or "Block"
	if shape == "Wedge" then
		part = Instance.new("WedgePart")
	elseif shape == "Corner" then
		part = Instance.new("CornerWedgePart")
	else
		local p = Instance.new("Part")
		if shape == "Ball" then
			p.Shape = Enum.PartType.Ball
		elseif shape == "Cylinder" then
			p.Shape = Enum.PartType.Cylinder
		end
		part = p
	end
	part.Name = o.name or "Part"
	part.Anchored = true
	part.CanCollide = o.collide == true
	part.CanTouch = false
	part.CanQuery = o.collide == true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = o.size or Vector3.new(4, 1, 4)
	part.CFrame = o.cf or CFrame.new()
	part.Color = o.color or Color3.fromRGB(120, 120, 130)
	part.Material = if o.neon then Enum.Material.Neon else (o.material or Enum.Material.Metal)
	part.Transparency = o.transparency or 0
	part.Reflectance = o.reflectance or 0
	part.CastShadow = if o.castShadow == nil then not o.neon else o.castShadow
	part.Parent = parent
	return part
end

-- A cylinder standing upright (axis along Y). size = (diameter, height).
function Build.pillar(parent: Instance, name: string, pos: Vector3, diameter: number, height: number, o: PartOpts?): BasePart
	local opts: PartOpts = o or {}
	opts.name = name
	opts.shape = "Cylinder"
	opts.size = Vector3.new(height, diameter, diameter)
	opts.cf = CFrame.new(pos + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	return Build.part(parent, opts)
end

-- A flat disc lying on the ground. size = (diameter, thickness).
function Build.disc(parent: Instance, name: string, pos: Vector3, diameter: number, thickness: number, o: PartOpts?): BasePart
	local opts: PartOpts = o or {}
	opts.name = name
	opts.shape = "Cylinder"
	opts.size = Vector3.new(thickness, diameter, diameter)
	opts.cf = CFrame.new(pos + Vector3.new(0, thickness / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	return Build.part(parent, opts)
end

function Build.model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

function Build.folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

function Build.light(part: BasePart, color: Color3, brightness: number, range: number): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Shadows = false
	l.Parent = part
	return l
end

function Build.emitter(part: BasePart, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = part
	return e
end

function Build.tag(inst: Instance, tag: string)
	CollectionService:AddTag(inst, tag)
end

-- ProximityPrompt that opens a UI panel on the client (attribute "Panel" names the panel).
function Build.prompt(part: BasePart, action: string, object: string, panel: string, holdSeconds: number?, range: number?): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = holdSeconds or 0
	p.MaxActivationDistance = range or 14
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p:SetAttribute("Panel", panel)
	p.Parent = part
	return p
end

-- Terrain surface height at (x, z); nil over open water / outside the islands.
function Build.groundY(x: number, z: number): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, 120, z), Vector3.new(0, -260, 0), params)
	if hit and hit.Material ~= Enum.Material.Water then
		return hit.Position.Y
	end
	return nil
end

-- A sign: a thin panel with a SurfaceGui label facing -Z of the given CFrame.
function Build.sign(parent: Instance, text: string, cf: CFrame, size: Vector3, color: Color3, textColor: Color3?): BasePart
	local panel = Build.part(parent, { name = "Sign", size = size, cf = cf, color = color, material = Enum.Material.Metal })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = panel
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = textColor or Color3.fromRGB(255, 236, 200)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.Parent = gui
	return panel
end

local meshCache: { [string]: MeshPart? } = {}

-- Places an AI-generated mesh from Config/Assets (uniformly scaled by `scale`). Returns nil when the asset cannot be
-- loaded so callers can fall back to a primitive build.
function Build.mesh(parent: Instance, key: string, cf: CFrame, scale: number, collide: boolean?): MeshPart?
	local info = Assets.Meshes[key]
	if not info then
		return nil
	end
	local template = meshCache[key]
	if template == nil then
		local ok, mesh = pcall(function()
			return AssetService:CreateMeshPartAsync(info.mesh :: any, { CollisionFidelity = Enum.CollisionFidelity.Box })
		end)
		if not (ok and mesh) then
			warn(`[ARMFORGE] mesh {key} failed to load, using fallback`)
			return nil
		end
		if info.texture then
			mesh.TextureID = info.texture :: any
		end
		meshCache[key] = mesh
		template = mesh
	end
	local part = (template :: MeshPart):Clone()
	part.Name = key
	part.Anchored = true
	part.Size = info.size * scale
	part.CFrame = cf
	part.CanCollide = collide == true
	part.CanQuery = collide == true
	part.CanTouch = false
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = parent
	return part
end

-- Deterministic pseudo random in [0,1) from integers (stable decoration layouts).
function Build.hash(a: number, b: number?): number
	local n = math.sin(a * 127.1 + (b or 0) * 311.7) * 43758.5453
	return n - math.floor(n)
end

-- Lays points evenly on a circle.
function Build.ringPoints(center: Vector3, radius: number, count: number, startAngle: number?): { Vector3 }
	local pts = {}
	for i = 0, count - 1 do
		local a = (startAngle or 0) + (i / count) * math.pi * 2
		table.insert(pts, center + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius))
	end
	return pts
end

return Build
