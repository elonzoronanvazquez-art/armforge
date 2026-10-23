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

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local Creatures = require(Shared.Config.Creatures)

local CreatureBuilder = {}

CreatureBuilder.TAG = "ArmRock" -- creatures are targeted exactly like rocks (same id space)
CreatureBuilder.CREATURE_TAG = "ArmCreature"

type Ctx = {
	model: Model,
	def: Creatures.CreatureDef,
	s: number,
	root: Part,
}

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
	local body = make(ctx, ctx.root, "Body", Vector3.new(3.4, 1.7, 5), CFrame.new(0, 1.9, 0), v.body, v.material)
	make(ctx, body, "PlateA", Vector3.new(3.0, 0.7, 2.0), CFrame.new(0, 1.0, -0.9) * CFrame.Angles(math.rad(-8), 0, 0), v.plate, v.material, { plate = true })
	make(ctx, body, "PlateB", Vector3.new(2.6, 0.6, 1.7), CFrame.new(0, 0.95, 1.3) * CFrame.Angles(math.rad(10), 0, 0), v.plate, v.material, { plate = true })
	make(ctx, body, "Core", Vector3.new(1.1, 0.5, 1.1), CFrame.new(0, 0.95, 0.2), v.glow, v.material, { glow = true })
	local head = make(ctx, body, "Head", Vector3.new(2.2, 1.5, 2.1), CFrame.new(0, 0.1, -3.1), darker(v.body, 0.1), v.material)
	eyes(ctx, head, -1.1, 0.25, 0.55, v.glow)
	make(ctx, head, "Jaw", Vector3.new(1.8, 0.45, 1.5), CFrame.new(0, -0.8, -0.4), v.plate, v.material)
	local tail = make(ctx, body, "Tail", Vector3.new(0.9, 0.8, 2.6), CFrame.new(0, 0.2, 3.2) * CFrame.Angles(math.rad(-15), 0, 0), v.plate, v.material, { pivotTop = false })
	make(ctx, tail, "TailTip", Vector3.new(0.5, 0.5, 1.2), CFrame.new(0, 0.2, 1.8), v.glow, v.material, { glow = true })
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
	local body = make(ctx, ctx.root, "Body", Vector3.new(3.6, 3.0, 2.6), CFrame.new(0, 3.9, 0), v.body, v.material)
	make(ctx, body, "Chest", Vector3.new(2.6, 2.0, 0.6), CFrame.new(0, 0.3, -1.4), v.plate, v.material, { plate = true })
	make(ctx, body, "Core", Vector3.new(1.0, 1.0, 0.5), CFrame.new(0, 0.3, -1.75), v.glow, v.material, { glow = true, shape = Enum.PartType.Ball })
	make(ctx, body, "Back", Vector3.new(2.4, 2.2, 0.8), CFrame.new(0, 0.4, 1.5), darker(v.plate, 0.2), v.material, { plate = true })
	make(ctx, body, "Vent", Vector3.new(1.6, 0.4, 0.3), CFrame.new(0, 1.0, 1.95), v.glow, v.material, { glow = true })
	local head = make(ctx, body, "Head", Vector3.new(1.9, 1.6, 1.8), CFrame.new(0, 2.5, -0.1), darker(v.body, 0.1), v.material)
	eyes(ctx, head, -0.95, 0.15, 0.45, v.glow)
	for _, side in { -1, 1 } do
		local n = if side < 0 then "L" else "R"
		make(ctx, body, "Pauldron" .. n, Vector3.new(1.8, 1.0, 2.0), CFrame.new(side * 2.3, 1.4, 0), v.plate, v.material, { plate = true })
		local arm = make(ctx, body, "Arm" .. n, Vector3.new(1.3, 2.6, 1.3), CFrame.new(side * 2.5, 1.0, 0), darker(v.body, 0.1), v.material, { pivotTop = true })
		make(ctx, arm, "Fist" .. n, Vector3.new(2.1, 1.9, 2.1), CFrame.new(0, -2.9, 0), v.plate, v.material, { plate = true })
		local leg = make(ctx, body, "Leg" .. n, Vector3.new(1.5, 2.6, 1.6), CFrame.new(side * 1.0, -1.4, 0), darker(v.body, 0.2), v.material, { pivotTop = true })
		make(ctx, leg, "Foot" .. n, Vector3.new(1.9, 0.7, 2.4), CFrame.new(0, -2.6, -0.3), v.plate, v.material)
	end
end

local function shard(ctx: Ctx)
	local v = ctx.def.visual
	local core = make(ctx, ctx.root, "Body", Vector3.new(2.4, 2.4, 2.4), CFrame.new(0, 3.4, 0), v.glow, v.material, { glow = true, shape = Enum.PartType.Ball })
	core.Transparency = 0.1
	make(ctx, core, "Core", Vector3.new(1.3, 1.3, 1.3), CFrame.identity, Color3.new(1, 1, 1), v.material, { glow = true, shape = Enum.PartType.Ball })
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
	local body = make(ctx, ctx.root, "Body", Vector3.new(4.2, 3.8, 3.0), CFrame.new(0, 4.6, 0), v.body, v.material)
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
	for _, side in { -1, 1 } do
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
	local ctx: Ctx = { model = model, def = def, s = def.scale, root = root }
	local template = templates[def.archetype]
	assert(template, `no body template for archetype {def.archetype}`)
	template(ctx)
	return model
end

function CreatureBuilder.tag(model: Model)
	CollectionService:AddTag(model, CreatureBuilder.TAG)
	CollectionService:AddTag(model, CreatureBuilder.CREATURE_TAG)
end

CreatureBuilder.templates = templates

return CreatureBuilder
