--!strict
-- Builds an arm set's visuals. Used by the SERVER to attach the equipped set to a character (replicates to everyone) and
-- by the CLIENT to render previews in the arm collection UI. Equipping always goes through attach(), which first
-- destroys the previous ArmforgeArms model, so arms never accumulate on a character.

local Shared = script.Parent.Parent
local Arms = require(Shared.Config.Arms)
local Assets = require(Shared.Config.Assets)
local ArmDesigns = require(script.Parent.ArmDesigns)

local ArmBuilder = {}

export type Recipe = {
	armId: string,
	primary: Color3,
	secondary: Color3,
	glow: Color3,
	trailColor: Color3,
	material: Enum.Material,
	reflectance: number,
	glowScale: number,
	tier: number,
	tint: Color3?,
}

ArmBuilder.MODEL_NAME = "ArmforgeArms"

local LIMBS = { "UpperArm", "LowerArm", "Hand" }

-- Nominal R15 proportions (measured in Studio) used for previews.
ArmBuilder.NominalSizes = {
	UpperArm = Vector3.new(1, 1.24, 1),
	LowerArm = Vector3.new(1, 1.12, 1),
	Hand = Vector3.new(0.98, 0.32, 1.03),
}
ArmBuilder.NominalCFrames = {
	UpperArm = CFrame.new(0, -0.62, 0),
	LowerArm = CFrame.new(0, -1.80, 0),
	Hand = CFrame.new(0, -2.52, 0),
}

-- Reflects an offset across the X axis (right arm -> left arm).
local function mirror(cf: CFrame): CFrame
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	return CFrame.new(-x, y, z, r00, -r01, -r02, -r10, r11, r12, -r20, r21, r22)
end

local function slotColor(recipe: Recipe, slot: string): Color3
	if slot == "primary" then
		return recipe.primary
	elseif slot == "secondary" then
		return recipe.secondary
	elseif slot == "dark" then
		return recipe.primary:Lerp(Color3.new(0, 0, 0), 0.45)
	end
	return recipe.glow
end

local function glowColor(recipe: Recipe, base: Color3): Color3
	local s = recipe.glowScale
	if s >= 1 then
		return base:Lerp(Color3.new(1, 1, 1), math.clamp((s - 1) * 0.3, 0, 0.3))
	end
	return base:Lerp(Color3.new(0, 0, 0), (1 - s) * 0.5)
end

local meshTemplates: { [string]: MeshPart? } = {}

local function meshTemplate(key: string): MeshPart?
	if meshTemplates[key] ~= nil then
		return meshTemplates[key]
	end
	local info = Assets.Meshes[key]
	if not info then
		return nil
	end
	local ok, mesh = pcall(function()
		return game:GetService("AssetService"):CreateMeshPartAsync(info.mesh :: any)
	end)
	if ok and mesh then
		if info.texture then
			mesh.TextureID = info.texture :: any
		end
		meshTemplates[key] = mesh
		return mesh
	end
	meshTemplates[key] = nil
	return nil
end

-- Creates one piece part (without positioning it). Returns nil for a mesh piece whose asset cannot be loaded.
local function makePart(p: ArmDesigns.Piece, recipe: Recipe): BasePart?
	local part: BasePart? = nil
	if p.mesh then
		local tpl = meshTemplate(p.mesh)
		if tpl then
			part = tpl:Clone()
		elseif p.kind == "Mesh" then
			return nil
		end
	end
	if part == nil then
		if p.kind == "Wedge" then
			part = Instance.new("WedgePart")
		elseif p.kind == "Ball" then
			local b = Instance.new("Part")
			b.Shape = Enum.PartType.Ball
			part = b
		elseif p.kind == "Cylinder" then
			local c = Instance.new("Part")
			c.Shape = Enum.PartType.Cylinder
			part = c
		else
			part = Instance.new("Part")
		end
	end
	local out: BasePart = part :: BasePart
	local isMesh = out:IsA("MeshPart") and p.mesh ~= nil
	out.Size = p.size
	out.Anchored = false
	out.CanCollide = false
	out.CanTouch = false
	out.CanQuery = false
	out.Massless = true
	out.CastShadow = not p.neon
	out.TopSurface = Enum.SurfaceType.Smooth
	out.BottomSurface = Enum.SurfaceType.Smooth
	local base = slotColor(recipe, p.slot)
	if isMesh then
		-- AI meshes carry their own baked texture; palettes only tint it
		out.Material = if recipe.reflectance > 0 then recipe.material else Enum.Material.SmoothPlastic
		out.Reflectance = recipe.reflectance
		out.Color = if recipe.tint then Color3.new(1, 1, 1):Lerp(recipe.tint, 0.55) else Color3.new(1, 1, 1)
		return out
	end
	local part2: BasePart = out
	if p.neon then
		part2.Material = Enum.Material.Neon
		part2.Color = glowColor(recipe, base)
	elseif p.glass then
		part2.Material = Enum.Material.Glass
		part2.Color = base
		part2.Transparency = 0.15
		part2.Reflectance = 0.2
	else
		part2.Material = recipe.material
		part2.Color = base
		part2.Reflectance = recipe.reflectance
	end
	return part2
end

local function particleFor(kind: string, color: Color3, scale: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.LightEmission = 0.6
	e.Lifetime = NumberRange.new(0.5, 1.1)
	e.Speed = NumberRange.new(0.5, 2)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.28), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.Rate = 8 * scale
	e.SpreadAngle = Vector2.new(180, 180)
	e.RotSpeed = NumberRange.new(-90, 90)
	e.LockedToPart = false
	if kind == "Embers" then
		e.Acceleration = Vector3.new(0, 4, 0)
		e.Rate = 14 * scale
		e.Speed = NumberRange.new(1, 3)
	elseif kind == "Steam" then
		e.Color = ColorSequence.new(Color3.fromRGB(230, 235, 240))
		e.LightEmission = 0
		e.Rate = 3 * scale
		e.Acceleration = Vector3.new(0, 2, 0)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0.9) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	elseif kind == "Dust" then
		e.Color = ColorSequence.new(Color3.fromRGB(180, 170, 160))
		e.LightEmission = 0
		e.Rate = 2 * scale
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.6) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) })
	elseif kind == "Stars" then
		e.Rate = 10 * scale
		e.Speed = NumberRange.new(0.2, 1.2)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 0) })
		e.LightEmission = 1
	elseif kind == "Sparkle" then
		e.Rate = 9 * scale
		e.Speed = NumberRange.new(0.2, 1.5)
		e.LightEmission = 1
	end
	return e
end

-- Core: creates the pieces for one side. `limbCFs` are the world CFrames the offsets are relative to.
local function buildSide(
	recipe: Recipe,
	side: string,
	limbs: { [string]: BasePart },
	container: Instance,
	anchored: boolean,
	limbCFs: { [string]: CFrame }?
)
	local design = ArmDesigns.Designs[recipe.armId]
	if not design then
		return
	end
	-- primitive stand-ins are only built when an AI mesh for this design could not be loaded
	local meshOk = true
	for _, p in design do
		if p.kind == "Mesh" and p.mesh and meshTemplate(p.mesh) == nil then
			meshOk = false
		end
	end
	for i, p in design do
		if (p.tier or 0) <= recipe.tier and not (p.fallback and meshOk and ArmDesigns.hasMesh(recipe.armId)) then
			local limb = limbs[p.limb]
			local part = if limb then makePart(p, recipe) else nil
			if limb and part then
				part.Name = `{side}{p.limb}{i}`
				local cf = if side == "L" then mirror(p.cf) else p.cf
				local base = if limbCFs then limbCFs[p.limb] else limb.CFrame
				part.CFrame = base * cf
				if anchored then
					part.Anchored = true
				else
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = limb
					weld.Part1 = part
					weld.Parent = part
				end
				part.Parent = container
			end
		end
	end

	-- hand-mounted effects: invisible anchor part with trail attachments, particles and light
	local hand = limbs.Hand
	if hand then
		local fx = Instance.new("Part")
		fx.Name = `{side}Fx`
		fx.Size = Vector3.new(0.4, 0.4, 0.4)
		fx.Transparency = 1
		fx.CanCollide = false
		fx.CanTouch = false
		fx.CanQuery = false
		fx.Massless = true
		fx.Anchored = anchored
		local base = if limbCFs then limbCFs.Hand else hand.CFrame
		fx.CFrame = base * CFrame.new(0, -1.0, 0)
		if not anchored then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = hand
			weld.Part1 = fx
			weld.Parent = fx
		end
		local a0 = Instance.new("Attachment")
		a0.Name = "TrailA"
		a0.Position = Vector3.new(0.8, 0, 0)
		a0.Parent = fx
		local a1 = Instance.new("Attachment")
		a1.Name = "TrailB"
		a1.Position = Vector3.new(-0.8, 0, 0)
		a1.Parent = fx
		local trail = Instance.new("Trail")
		trail.Name = "StrikeTrail"
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = ColorSequence.new(recipe.trailColor)
		trail.LightEmission = 0.8
		trail.Lifetime = 0.28
		trail.MinLength = 0.05
		trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
		trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.1) })
		trail.Enabled = false
		trail.Parent = fx
		local effects = ArmDesigns.Effects[recipe.armId]
		if effects and effects.particle then
			local e = particleFor(effects.particle, recipe.trailColor, recipe.glowScale * (1 + recipe.tier * 0.3))
			e.Parent = fx
		end
		if effects and effects.light then
			local light = Instance.new("PointLight")
			light.Color = recipe.glow
			light.Brightness = effects.light * recipe.glowScale
			light.Range = 7 + recipe.tier
			light.Shadows = false
			light.Parent = fx
		end
		fx.Parent = container
	end
end

local function limbsOf(character: Model, side: string): { [string]: BasePart }?
	local out: { [string]: BasePart } = {}
	local prefix = if side == "R" then "Right" else "Left"
	for _, limb in LIMBS do
		local part = character:FindFirstChild(prefix .. limb)
		if not (part and part:IsA("BasePart")) then
			return nil
		end
		out[limb] = part
	end
	return out
end

-- Removes whatever arm set is on the character and restores the real limbs.
function ArmBuilder.detach(character: Model)
	local old = character:FindFirstChild(ArmBuilder.MODEL_NAME)
	while old do
		old:Destroy()
		old = character:FindFirstChild(ArmBuilder.MODEL_NAME)
	end
	for _, side in { "Right", "Left" } do
		for _, limb in LIMBS do
			local part = character:FindFirstChild(side .. limb)
			if part and part:IsA("BasePart") then
				part.Transparency = 0
			end
		end
	end
end

-- Equips `recipe` on the character, REPLACING any previous set. Returns the new model (nil for non-R15 rigs).
function ArmBuilder.attach(character: Model, recipe: Recipe): Model?
	local right = limbsOf(character, "R")
	local left = limbsOf(character, "L")
	if not right or not left then
		return nil
	end
	ArmBuilder.detach(character)
	local model = Instance.new("Model")
	model.Name = ArmBuilder.MODEL_NAME
	model:SetAttribute("ArmId", recipe.armId)
	model:SetAttribute("Tier", recipe.tier)
	for _, limbs in { right, left } do
		for _, part in limbs do
			part.Transparency = 1
		end
	end
	buildSide(recipe, "R", right, model, false, nil)
	buildSide(recipe, "L", left, model, false, nil)
	model.Parent = character
	return model
end

-- Standalone display (arms hanging from the origin) for viewport previews.
function ArmBuilder.buildDisplay(recipe: Recipe, side: string?): Model
	local model = Instance.new("Model")
	model.Name = "ArmDisplay"
	local limbs: { [string]: BasePart } = {}
	for _, limb in LIMBS do
		local part = Instance.new("Part")
		part.Name = limb
		part.Size = ArmBuilder.NominalSizes[limb]
		part.CFrame = ArmBuilder.NominalCFrames[limb]
		part.Transparency = 1
		part.Anchored = true
		part.CanCollide = false
		part.Parent = model
		limbs[limb] = part
	end
	buildSide(recipe, side or "R", limbs, model, true, ArmBuilder.NominalCFrames)
	return model
end

function ArmBuilder.currentArmId(character: Model): string?
	local m = character:FindFirstChild(ArmBuilder.MODEL_NAME)
	return m and m:GetAttribute("ArmId") :: string?
end

-- All the trails of the attached arms, keyed "R" / "L".
function ArmBuilder.trails(character: Model): { [string]: Trail }
	local out: { [string]: Trail } = {}
	local m = character:FindFirstChild(ArmBuilder.MODEL_NAME)
	if m then
		for _, side in { "R", "L" } do
			local fx = m:FindFirstChild(side .. "Fx")
			local t = fx and fx:FindFirstChild("StrikeTrail")
			if t and t:IsA("Trail") then
				out[side] = t
			end
		end
	end
	return out
end

-- Visual recipe from raw arm id (used where no player data exists, e.g. showcase pedestals).
function ArmBuilder.defaultRecipe(armId: string): Recipe
	local def = Arms.Defs[armId]
	return {
		armId = armId,
		primary = def.palette.primary,
		secondary = def.palette.secondary,
		glow = def.palette.glow,
		trailColor = def.palette.glow,
		material = def.material,
		reflectance = 0,
		glowScale = 1,
		tier = 0,
	}
end

return ArmBuilder
