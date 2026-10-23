--!strict
-- Builds creature models from procedural body templates (crawler, brute, shard, titan), tinted and detailed from the creature
-- definition. The model's root is an anchored, non-colliding part at the creature's feet; every other part hangs off it on a
-- Motor6D named J_<Part>, so the CLIENT can animate the creature locally (Motor6D.Transform is not replicated) while the
-- server only moves the root and publishes state attributes. Nothing here is a custom animation asset: the animation is
-- procedural (client/Controllers/CreatureController).
--
-- A body can optionally be replaced by an AI-generated mesh (`visual.mesh` -> Config/Assets.Meshes); if that asset is missing or
-- fails to load the procedural body remains, so a creature always renders.

local CollectionService = game:GetService("CollectionService")
local AssetService = game:GetService("AssetService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local Creatures = require(Shared.Config.Creatures)
local Assets = require(Shared.Config.Assets)
local CreatureRigs = require(Shared.Config.CreatureRigs)

local CreatureBuilder = {}

CreatureBuilder.TAG = "ArmRock" -- creatures are targeted exactly like rocks (same id space)
CreatureBuilder.CREATURE_TAG = "ArmCreature"

type Ctx = {
	model: Model,
	def: Creatures.CreatureDef,
	s: number,
	root: Part,
	meshBody: boolean, -- an AI body mesh replaced the procedural torso (and head), so those decorations are skipped
	wholeBody: boolean, -- the mesh also has arms and legs, so the procedural limbs are skipped too
	rigged: boolean, -- built from a segmented AI rig (limbs animate)
}

-- AI body meshes (Config/Assets.Meshes). A mesh that fails to load leaves the procedural body in place.
local meshTemplates: { [string]: MeshPart | boolean } = {}

local function meshTemplate(key: string): MeshPart?
	local cached = meshTemplates[key]
	if cached ~= nil then
		return if cached == false then nil else cached :: MeshPart
	end
	local info = Assets.Meshes[key]
	if not info then
		meshTemplates[key] = false
		return nil
	end
	local ok, mesh = pcall(function()
		return AssetService:CreateMeshPartAsync(info.mesh :: any, { CollisionFidelity = Enum.CollisionFidelity.Box })
	end)
	if not (ok and mesh) then
		warn(`[ARMFORGE] creature mesh {key} failed to load; using the procedural body`)
		meshTemplates[key] = false
		return nil
	end
	if info.texture then
		mesh.TextureID = info.texture :: any
	end
	meshTemplates[key] = mesh
	return mesh
end

type Opts = { pivotTop: boolean?, shape: Enum.PartType?, glow: boolean?, plate: boolean? }

local function make(ctx: Ctx, parent: BasePart, name: string, size: Vector3, c0: CFrame, color: Color3, material: Enum.Material, opts: Opts?): Part
	local o: Opts = opts or {}
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size * ctx.s
	p.Color = color
	p.Material = material
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = not o.glow
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if o.shape then
		p.Shape = o.shape
	end
	if o.glow then
		p.Material = Enum.Material.Neon
		p:SetAttribute("Glow", true)
	end
	if o.plate then
		p:SetAttribute("Plate", true)
	end
	p.Parent = ctx.model
	local m = Instance.new("Motor6D")
	m.Name = "J_" .. name
	m.Part0 = parent
	m.Part1 = p
	m.C0 = CFrame.new(c0.Position * ctx.s) * (c0 - c0.Position)
	m.C1 = if o.pivotTop then CFrame.new(0, p.Size.Y / 2, 0) else CFrame.identity
	m.Parent = p
	return p
end

-- The torso: the creature's AI mesh when it has one (scaled to the template's body size), else the procedural block.
local function makeBody(ctx: Ctx, size: Vector3, c0: CFrame): BasePart
	local v = ctx.def.visual
	local tpl = if v.mesh then meshTemplate(v.mesh) else nil
	if tpl then
		local p = tpl:Clone()
		p.Name = "Body"
		p.Size = size * ctx.s
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = true
		p.Parent = ctx.model
		local m = Instance.new("Motor6D")
		m.Name = "J_Body"
		m.Part0 = ctx.root
		m.Part1 = p
		m.C0 = CFrame.new(c0.Position * ctx.s) * CFrame.Angles(0, math.rad(v.meshYaw or 0), 0)
		if v.meshLimbs then
			-- a whole-body mesh (it has its own arms and legs): scale it to the creature's height and stand it on the ground
			local info = Assets.Meshes[v.mesh :: string]
			local native = info.size
			local k = ctx.def.height / native.Y
			p.Size = native * k
			m.C0 = CFrame.new(0, p.Size.Y / 2 + 0.15, 0) * CFrame.Angles(0, math.rad(v.meshYaw or 0), 0)
			ctx.wholeBody = true
		end
		m.Parent = p
		ctx.meshBody = true
		return p
	end
	return make(ctx, ctx.root, "Body", size, c0, v.body, v.material)
end

-- Segmented AI rigs ---------------------------------------------------------------------------------------------------------------------
-- A rig is the set of separate MeshParts Studio generated (torso, head, arms, legs...). Each keeps the CFrame it was generated at;
-- here they are scaled to the creature's height, turned to face -Z and joined by Motor6Ds named like the procedural templates
-- (J_Body, J_Head, J_ArmL, J_LegR...), so the client animation drives both kinds of creature identically. Joint frames are aligned
-- to the creature (not to the mesh), so a positive rotation about X always swings a limb forward.

local rigPartTemplates: { [string]: MeshPart | boolean } = {}

local function rigPartTemplate(part: CreatureRigs.Part): MeshPart?
	local cached = rigPartTemplates[part.mesh]
	if cached ~= nil then
		return if cached == false then nil else cached :: MeshPart
	end
	local ok, mesh = pcall(function()
		return AssetService:CreateMeshPartAsync(part.mesh :: any, { CollisionFidelity = Enum.CollisionFidelity.Box })
	end)
	if not (ok and mesh) then
		warn(`[ARMFORGE] rig mesh {part.mesh} ({part.name}) failed to load`)
		rigPartTemplates[part.mesh] = false
		return nil
	end
	if part.texture ~= "" then
		mesh.TextureID = part.texture :: any
	end
	rigPartTemplates[part.mesh] = mesh
	return mesh
end

local ROLE_JOINT: { [string]: string } = {
	torso = "Body",
	body = "Body",
	head = "Head",
	["left arm"] = "ArmL",
	["right arm"] = "ArmR",
	["left leg"] = "LegL",
	["right leg"] = "LegR",
	tail = "Tail",
}

-- Where a part swings from, in the rig's own space (before scaling): shoulders and hips near the top of the limb, the neck at
-- the bottom of the head, the hips at the bottom of the torso, a tail where it meets the body.
local function pivotFor(role: string, cf: CFrame, size: Vector3, bodyPos: Vector3): Vector3
	local p = cf.Position
	if role == "Body" then
		return p - Vector3.new(0, size.Y / 2, 0)
	elseif role == "Head" then
		return p - Vector3.new(0, size.Y / 2, 0)
	elseif role == "ArmL" or role == "ArmR" then
		return p + Vector3.new(0, size.Y * 0.3, 0)
	elseif role == "Tail" then
		local toBody = bodyPos - p
		return p + (if math.abs(toBody.Z) >= math.abs(toBody.X) then Vector3.new(0, 0, math.sign(toBody.Z) * size.Z / 2) else Vector3.new(math.sign(toBody.X) * size.X / 2, 0, 0))
	end
	return p + Vector3.new(0, size.Y * 0.42, 0) -- legs
end

local function buildRig(ctx: Ctx, rigKey: string): boolean
	local rig = CreatureRigs.Defs[rigKey]
	if not rig then
		return false
	end
	local templates: { MeshPart } = {}
	for i, part in rig.parts do
		local tpl = rigPartTemplate(part)
		if not tpl then
			return false
		end
		templates[i] = tpl
	end
	local def = ctx.def
	local k = def.height / rig.bbox.Y
	local yaw = CFrame.Angles(0, math.rad(def.visual.meshYaw or 0), 0)
	local lift = CFrame.new(0, def.height / 2 + 0.12, 0)
	local function world(cf: CFrame): CFrame
		return lift * yaw * CFrame.new(cf.Position * k) * (cf - cf.Position)
	end
	-- the body first: everything else hangs from it
	local bodyIndex = 0
	for i, part in rig.parts do
		if ROLE_JOINT[part.name] == "Body" then
			bodyIndex = i
		end
	end
	if bodyIndex == 0 then
		return false
	end
	local bodyPart = rig.parts[bodyIndex]
	local bodyWorld = world(bodyPart.cf)
	local bodyPos = bodyPart.cf.Position
	local built: { [string]: BasePart } = {}
	local order: { number } = { bodyIndex }
	for i in rig.parts do
		if i ~= bodyIndex then
			table.insert(order, i)
		end
	end
	for _, i in order do
		local part = rig.parts[i]
		local role = ROLE_JOINT[part.name]
		if not role then
			-- four-legged rigs: "front left leg" etc.; the end nearer the head is the front
			local front = part.name:find("front", 1, true) ~= nil
			local left = part.name:find("left", 1, true) ~= nil
			if part.name:find("leg", 1, true) then
				role = (if front then "LegF" else "LegB") .. (if left then "L" else "R")
			else
				role = part.name
			end
		end
		local mesh = templates[i]:Clone()
		mesh.Name = role
		mesh.Size = part.size * k
		mesh.Anchored = false
		mesh.CanCollide = false
		mesh.CanQuery = false
		mesh.CanTouch = false
		mesh.Massless = true
		mesh.CastShadow = true
		mesh.Parent = ctx.model
		local partWorld = world(part.cf)
		local pivot = lift * yaw * CFrame.new(pivotFor(role, part.cf, part.size, bodyPos) * k)
		local pivotFrame = CFrame.new(pivot.Position)
		local motor = Instance.new("Motor6D")
		motor.Name = "J_" .. role
		if i == bodyIndex then
			motor.Part0 = ctx.root
			motor.C0 = pivotFrame
		else
			motor.Part0 = built.Body
			motor.C0 = bodyWorld:Inverse() * pivotFrame
		end
		motor.Part1 = mesh
		motor.C1 = partWorld:Inverse() * pivotFrame
		motor.Parent = mesh
		built[role] = mesh
	end
	ctx.meshBody = true
	ctx.wholeBody = true
	ctx.rigged = true
	return true
end

local function darker(c: Color3, k: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), k)
end

local function eyes(ctx: Ctx, head: BasePart, z: number, y: number, spread: number, glow: Color3)
	for _, side in { -1, 1 } do
		make(ctx, head, if side < 0 then "EyeL" else "EyeR", Vector3.new(0.35, 0.3, 0.2), CFrame.new(side * spread, y, z), glow, Enum.Material.Neon, { glow = true })
	end
end

-- Templates -------------------------------------------------------------------------------------------------------------

local function crawler(ctx: Ctx)
	local v = ctx.def.visual
	local body = makeBody(ctx, Vector3.new(3.4, 2.0, 5.2), CFrame.new(0, 1.9, 0))
	if not ctx.meshBody then
		make(ctx, body, "PlateA", Vector3.new(3.0, 0.7, 2.0), CFrame.new(0, 1.0, -0.9) * CFrame.Angles(math.rad(-8), 0, 0), v.plate, v.material, { plate = true })
		make(ctx, body, "PlateB", Vector3.new(2.6, 0.6, 1.7), CFrame.new(0, 0.95, 1.3) * CFrame.Angles(math.rad(10), 0, 0), v.plate, v.material, { plate = true })
		make(ctx, body, "Core", Vector3.new(1.1, 0.5, 1.1), CFrame.new(0, 0.95, 0.2), v.glow, v.material, { glow = true })
		local head = make(ctx, body, "Head", Vector3.new(2.2, 1.5, 2.1), CFrame.new(0, 0.1, -3.1), darker(v.body, 0.1), v.material)
		eyes(ctx, head, -1.1, 0.25, 0.55, v.glow)
		make(ctx, head, "Jaw", Vector3.new(1.8, 0.45, 1.5), CFrame.new(0, -0.8, -0.4), v.plate, v.material)
	else
		-- the mesh has its own head and plates; a small glowing back core marks the weak point the player should hit
		make(ctx, body, "Core", Vector3.new(1.0, 0.45, 1.0), CFrame.new(0, 1.05, 0.3), v.glow, v.material, { glow = true })
	end
	if not ctx.meshBody then
		local tail = make(ctx, body, "Tail", Vector3.new(0.9, 0.8, 2.6), CFrame.new(0, 0.2, 3.2) * CFrame.Angles(math.rad(-15), 0, 0), v.plate, v.material, { pivotTop = false })
		make(ctx, tail, "TailTip", Vector3.new(0.5, 0.5, 1.2), CFrame.new(0, 0.2, 1.8), v.glow, v.material, { glow = true })
	end
	local legs: { { x: number, z: number, name: string } } = {
		{ x = -1.6, z = -1.8, name = "LegFL" },
		{ x = 1.6, z = -1.8, name = "LegFR" },
		{ x = -1.6, z = 1.8, name = "LegBL" },
		{ x = 1.6, z = 1.8, name = "LegBR" },
	}
	for _, spec in legs do
		local leg = make(ctx, body, spec.name, Vector3.new(0.8, 1.9, 0.8), CFrame.new(spec.x, -0.6, spec.z), darker(v.body, 0.15), v.material, { pivotTop = true })
		make(ctx, leg, spec.name .. "Claw", Vector3.new(0.9, 0.35, 1.2), CFrame.new(0, -1.9, -0.25), v.plate, v.material)
	end
end

local function brute(ctx: Ctx)
	local v = ctx.def.visual
	local body = makeBody(ctx, Vector3.new(3.8, 3.2, 2.8), CFrame.new(0, 3.9, 0))
	if not ctx.meshBody then
		make(ctx, body, "Chest", Vector3.new(2.6, 2.0, 0.6), CFrame.new(0, 0.3, -1.4), v.plate, v.material, { plate = true })
		make(ctx, body, "Core", Vector3.new(1.0, 1.0, 0.5), CFrame.new(0, 0.3, -1.75), v.glow, v.material, { glow = true, shape = Enum.PartType.Ball })
		make(ctx, body, "Back", Vector3.new(2.4, 2.2, 0.8), CFrame.new(0, 0.4, 1.5), darker(v.plate, 0.2), v.material, { plate = true })
		make(ctx, body, "Vent", Vector3.new(1.6, 0.4, 0.3), CFrame.new(0, 1.0, 1.95), v.glow, v.material, { glow = true })
		local head = make(ctx, body, "Head", Vector3.new(1.9, 1.6, 1.8), CFrame.new(0, 2.5, -0.1), darker(v.body, 0.1), v.material)
		eyes(ctx, head, -0.95, 0.15, 0.45, v.glow)
	else
		make(ctx, body, "Core", Vector3.new(0.9, 0.9, 0.4), CFrame.new(0, 0.3, -1.5), v.glow, v.material, { glow = true, shape = Enum.PartType.Ball })
	end
	for _, side in { -1, 1 } do
		local n = if side < 0 then "L" else "R"
		local reach = if ctx.meshBody then 1.9 else 2.5 -- a mesh torso is narrower than the procedural block
		make(ctx, body, "Pauldron" .. n, Vector3.new(1.8, 1.0, 2.0), CFrame.new(side * (reach - 0.2), 1.4, 0), v.plate, v.material, { plate = true })
		local arm = make(ctx, body, "Arm" .. n, Vector3.new(1.3, 2.6, 1.3), CFrame.new(side * reach, 1.0, 0), darker(v.body, 0.1), v.material, { pivotTop = true })
		make(ctx, arm, "Fist" .. n, Vector3.new(2.1, 1.9, 2.1), CFrame.new(0, -2.9, 0), v.plate, v.material, { plate = true })
		local leg = make(ctx, body, "Leg" .. n, Vector3.new(1.5, 2.6, 1.6), CFrame.new(side * 1.0, -1.4, 0), darker(v.body, 0.2), v.material, { pivotTop = true })
		make(ctx, leg, "Foot" .. n, Vector3.new(1.9, 0.7, 2.4), CFrame.new(0, -2.6, -0.3), v.plate, v.material)
	end
end

local function shard(ctx: Ctx)
	local v = ctx.def.visual
	local core = make(ctx, ctx.root, "Body", Vector3.new(2.4, 2.4, 2.4), CFrame.new(0, 3.4, 0), v.glow, v.material, { glow = true, shape = Enum.PartType.Ball })
	core.Transparency = 0.1
	local crystal = if v.mesh then meshTemplate(v.mesh) else nil
	if crystal then
		-- an existing AI crystal mesh (Config/Assets) is the heart of this creature; the glow ball becomes its halo
		core.Transparency = 0.55
		local heart = crystal:Clone()
		heart.Name = "Core"
		heart.Size = Vector3.new(2.6, 3.4, 2.6) * ctx.s
		heart.Anchored = false
		heart.CanCollide = false
		heart.CanQuery = false
		heart.CanTouch = false
		heart.Massless = true
		heart.Parent = ctx.model
		local hm = Instance.new("Motor6D")
		hm.Name = "J_Core"
		hm.Part0 = core
		hm.Part1 = heart
		hm.Parent = heart
		heart:SetAttribute("Glow", true)
	else
		make(ctx, core, "Core", Vector3.new(1.3, 1.3, 1.3), CFrame.identity, Color3.new(1, 1, 1), v.material, { glow = true, shape = Enum.PartType.Ball })
	end
	local count = 7
	for i = 1, count do
		local a = (i / count) * math.pi * 2
		local r = 2.2
		local h = 2.6 + (i % 3) * 0.7
		local spike = make(
			ctx,
			core,
			"Spike" .. i,
			Vector3.new(0.7, h, 0.7),
			CFrame.new(math.cos(a) * r, (i % 2 == 0) and 0.5 or -0.4, math.sin(a) * r) * CFrame.Angles(math.rad(((i % 2 == 0) and 18 or -22)) * math.cos(a), 0, math.rad(((i % 2 == 0) and 18 or -22)) * math.sin(a)),
			if i % 2 == 0 then v.body else v.plate,
			v.material,
			{ plate = true }
		)
		spike.Transparency = 0.12
	end
	for i = 1, 3 do
		make(ctx, core, "Fang" .. i, Vector3.new(0.5, 1.6, 0.5), CFrame.new((i - 2) * 0.9, -1.8, -0.6) * CFrame.Angles(math.rad(10), 0, 0), v.plate, v.material, { plate = true })
	end
end

local function titan(ctx: Ctx)
	local v = ctx.def.visual
	local body = makeBody(ctx, Vector3.new(4.4, 4.2, 3.2), CFrame.new(0, 4.6, 0))
	if not ctx.meshBody then
		for i = 1, 5 do
			make(ctx, body, "Slab" .. i, Vector3.new(1.4, 0.9, 1.0), CFrame.new((i - 3) * 0.95, 2.05 + (i % 2) * 0.2, 0.3) * CFrame.Angles(0, 0, math.rad((i - 3) * 8)), v.plate, v.material, { plate = true })
		end
		make(ctx, body, "Chest", Vector3.new(3.2, 2.6, 0.8), CFrame.new(0, 0.2, -1.75), v.plate, v.material, { plate = true })
		make(ctx, body, "Core", Vector3.new(1.5, 1.5, 0.7), CFrame.new(0, 0.3, -2.2), v.glow, v.material, { glow = true, shape = Enum.PartType.Ball })
		make(ctx, body, "Back", Vector3.new(3.0, 3.0, 1.0), CFrame.new(0, 0.4, 1.9), darker(v.plate, 0.25), v.material, { plate = true })
		make(ctx, body, "Vent", Vector3.new(2.2, 0.5, 0.4), CFrame.new(0, 1.4, 2.5), v.glow, v.material, { glow = true })
		local head = make(ctx, body, "Head", Vector3.new(2.4, 1.9, 2.2), CFrame.new(0, 2.9, -0.2), darker(v.body, 0.1), v.material)
		eyes(ctx, head, -1.15, 0.2, 0.6, v.glow)
		make(ctx, head, "Crown", Vector3.new(2.6, 0.5, 1.2), CFrame.new(0, 1.1, 0.1), v.plate, v.material, { plate = true })
	elseif not ctx.wholeBody then
		make(ctx, body, "Core", Vector3.new(1.3, 1.3, 0.6), CFrame.new(0, 0.3, -1.9), v.glow, v.material, { glow = true, shape = Enum.PartType.Ball })
	end
	local sides: { number } = if ctx.wholeBody then {} else { -1, 1 }
	for _, side in sides do
		local n = if side < 0 then "L" else "R"
		make(ctx, body, "Pauldron" .. n, Vector3.new(2.4, 1.4, 2.6), CFrame.new(side * 3.1, 1.7, 0), v.plate, v.material, { plate = true })
		local arm = make(ctx, body, "Arm" .. n, Vector3.new(1.7, 3.4, 1.7), CFrame.new(side * 3.2, 1.2, 0), darker(v.body, 0.1), v.material, { pivotTop = true })
		make(ctx, arm, "Fist" .. n, Vector3.new(2.8, 2.5, 2.8), CFrame.new(0, -3.7, 0), v.plate, v.material, { plate = true })
		local leg = make(ctx, body, "Leg" .. n, Vector3.new(2.0, 3.4, 2.1), CFrame.new(side * 1.3, -1.8, 0), darker(v.body, 0.2), v.material, { pivotTop = true })
		make(ctx, leg, "Foot" .. n, Vector3.new(2.5, 0.9, 3.0), CFrame.new(0, -3.4, -0.4), v.plate, v.material)
	end
end

local templates: { [string]: (Ctx) -> () } = {
	crawler = crawler,
	brute = brute,
	shard = shard,
	titan = titan,
}

-- Builds the model at `pos` (the creature's feet). Returns the model; the caller parents and tags it.
function CreatureBuilder.build(def: Creatures.CreatureDef, id: number, pos: Vector3): Model
	local model = Instance.new("Model")
	model.Name = `Creature_{id}`
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(def.radius * 2, 0.4, def.radius * 2)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.CFrame = CFrame.new(pos)
	root.Parent = model
	model.PrimaryPart = root
	local ctx: Ctx = { model = model, def = def, s = def.scale, root = root, meshBody = false, wholeBody = false, rigged = false }
	local rigKey = def.visual.rig
	if not (rigKey and buildRig(ctx, rigKey)) then
		-- no rig, or one of its meshes failed to load: any partly built parts are discarded and the template takes over
		for _, child in model:GetChildren() do
			if child ~= root then
				child:Destroy()
			end
		end
		ctx.meshBody, ctx.wholeBody = false, false
		local template = templates[def.archetype]
		assert(template, `no body template for archetype {def.archetype}`)
		template(ctx)
	end
	model:SetAttribute("Rigged", ctx.rigged)
	return model
end

function CreatureBuilder.tag(model: Model)
	CollectionService:AddTag(model, CreatureBuilder.TAG)
	CollectionService:AddTag(model, CreatureBuilder.CREATURE_TAG)
end

CreatureBuilder.templates = templates

return CreatureBuilder
