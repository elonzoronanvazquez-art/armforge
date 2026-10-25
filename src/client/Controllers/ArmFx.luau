--!strict
-- Arm, signature, skill and creature visual effects: everything bigger than a spark. Cosmetic only and budgeted like
-- EffectsController (pooled parts, capped transient count, reduce-effects lowers every count). The shared pieces (flash, ring,
-- emit, sound) come from EffectsController; this module adds the streaks, pillars, bolts and particle kinds each arm needs
-- to look like itself:
--   Starter      knuckle stars and comic impact lines        Stonebreaker  quake rings, ground cracks, dust
--   Alloy        electric bolts and steam                    Crystal       prism shards and refracted beams
--   Magma        flame, embers and fire pillars              Void          rifts, implosions and tearing slashes

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local Arms = require(Shared.Config.Arms)
local Signatures = require(Shared.Config.Signatures)
local PoseMath = require(Shared.Logic.PoseMath)
local EffectsController = require(script.Parent.EffectsController)
local CameraController = require(script.Parent.CameraController)

local ArmFx = {}

local LOCAL = Players.LocalPlayer
local rng = Random.new()

local MAX_ACTIVE = 110

local WHITE = Color3.new(1, 1, 1)
local UP = Vector3.yAxis

-- Transient neon parts ---------------------------------------------------------------------------------------------------------

type Anim = { part: Part, kind: string, t0: number, life: number, update: (Part, number) -> () }

local active: { Anim } = {}
local pool: { [string]: { Part } } = { block = {}, cylinder = {}, ball = {} }

local function folder(): Folder
	return EffectsController.folder()
end

local function scale(): number
	return EffectsController.scale()
end

local function take(kind: string): Part
	local list = pool[kind]
	local p: Part? = table.remove(list)
	if p then
		return p
	end
	local created = Instance.new("Part")
	created.Anchored = true
	created.CanCollide = false
	created.CanQuery = false
	created.CanTouch = false
	created.CastShadow = false
	created.Material = Enum.Material.Neon
	created.TopSurface = Enum.SurfaceType.Smooth
	created.BottomSurface = Enum.SurfaceType.Smooth
	created.Name = "ArmFx_" .. kind
	if kind == "cylinder" then
		created.Shape = Enum.PartType.Cylinder
	elseif kind == "ball" then
		created.Shape = Enum.PartType.Ball
	end
	return created
end

local function spawn(kind: string, life: number, setup: (Part) -> (), update: (Part, number) -> ())
	if #active >= MAX_ACTIVE then
		return
	end
	local p = take(kind)
	setup(p)
	p.Parent = folder()
	table.insert(active, { part = p, kind = kind, t0 = os.clock(), life = life, update = update })
end

-- A glowing bar from a to b that thins and fades.
local function streak(a: Vector3, b: Vector3, color: Color3, width: number, life: number, alpha: number?)
	local len = (b - a).Magnitude
	if len < 0.05 then
		return
	end
	local a0 = alpha or 0.05
	spawn("block", life, function(p)
		p.Color = color
		p.Transparency = a0
		p.Size = Vector3.new(width, width, len)
		p.CFrame = CFrame.lookAt(a, b) * CFrame.new(0, 0, -len / 2)
	end, function(p, k)
		local w = width * (1 - k * 0.85)
		p.Size = Vector3.new(w, w, len)
		p.Transparency = a0 + (1 - a0) * k * k
	end)
end

-- A jagged chain of streaks (electricity).
local function bolt(a: Vector3, b: Vector3, color: Color3, width: number, life: number, segments: number, jitter: number)
	local prev = a
	for i = 1, segments do
		local f = i / segments
		local point = a:Lerp(b, f)
		if i < segments then
			point += Vector3.new(rng:NextNumber() - 0.5, rng:NextNumber() - 0.5, rng:NextNumber() - 0.5) * 2 * jitter
		end
		streak(prev, point, color, width, life)
		prev = point
	end
end

-- A vertical glowing column that swells and fades (fire pillars, soul lights, beams of light).
local function pillar(base: Vector3, color: Color3, diameter: number, height: number, life: number)
	spawn("cylinder", life, function(p)
		p.Color = color
		p.Transparency = 0.3
		p.Size = Vector3.new(height, diameter, diameter)
		p.CFrame = CFrame.new(base + UP * (height / 2)) * CFrame.Angles(0, 0, math.pi / 2)
	end, function(p, k)
		local d = diameter * (1 + k * 0.5) * (1 - k * k * 0.6)
		p.Size = Vector3.new(height * (1 + k * 0.3), d, d)
		p.CFrame = CFrame.new(base + UP * (height * (1 + k * 0.3) / 2)) * CFrame.Angles(0, 0, math.pi / 2)
		p.Transparency = 0.3 + 0.7 * k
	end)
end

-- Raycasts down for the ground under a point.
local function groundY(pos: Vector3): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { folder() }
	if LOCAL.Character then
		table.insert(ignore, LOCAL.Character)
	end
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -30, 0), params)
	return if hit then hit.Position.Y + 0.2 else pos.Y - 2.5
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 0.01 then f.Unit else Vector3.new(0, 0, -1)
end

-- Lines radiating along the ground from `center` (cracks, shock lines, scorch marks).
local function groundLines(center: Vector3, color: Color3, count: number, minLen: number, maxLen: number, width: number, life: number)
	local y = groundY(center)
	local n = math.max(1, math.floor(count * scale() + 0.5))
	for i = 1, n do
		local a = (i / n) * math.pi * 2 + rng:NextNumber() * 0.4
		local len = minLen + (maxLen - minLen) * rng:NextNumber()
		local from = Vector3.new(center.X, y, center.Z) + Vector3.new(math.cos(a), 0, math.sin(a)) * (minLen * 0.35)
		local mid = from + Vector3.new(math.cos(a + 0.18), 0, math.sin(a + 0.18)) * (len * 0.55)
		local to = mid + Vector3.new(math.cos(a - 0.2), 0, math.sin(a - 0.2)) * (len * 0.45)
		streak(from, mid, color, width, life, 0.05)
		streak(mid, to, color, width * 0.7, life, 0.1)
	end
end

-- Lines flying outward from a point on a surface (comic impact lines).
local function impactLines(pos: Vector3, normal: Vector3, color: Color3, count: number, minLen: number, maxLen: number, width: number, life: number)
	local n = math.max(1, math.floor(count * scale() + 0.5))
	local n0 = if normal.Magnitude > 0.01 then normal.Unit else UP
	for _ = 1, n do
		local rand = Vector3.new(rng:NextNumber() - 0.5, rng:NextNumber() - 0.5, rng:NextNumber() - 0.5)
		local d = (n0 * (0.5 + rng:NextNumber()) + rand * 1.6)
		if d.Magnitude > 0.01 then
			local dir = d.Unit
			local len = minLen + (maxLen - minLen) * rng:NextNumber()
			streak(pos + dir * 0.4, pos + dir * (0.4 + len), color, width, life)
		end
	end
end

-- Particle kinds ------------------------------------------------------------------------------------------------------------------

local emitters: { [string]: { part: Part, emitter: ParticleEmitter } } = {}

local function makeEmitter(kind: string, props: { [string]: any })
	local part = Instance.new("Part")
	part.Name = "ArmEmitter_" .. kind
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.4, 0.4, 0.4)
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.LockedToPart = false
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = part
	part.Parent = folder()
	emitters[kind] = { part = part, emitter = e }
end

local function setupEmitters()
	makeEmitter("steam", {
		Lifetime = NumberRange.new(0.6, 1.2),
		Speed = NumberRange.new(3, 9),
		SpreadAngle = Vector2.new(50, 50),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 3.4) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(Color3.fromRGB(235, 242, 248)),
		Acceleration = Vector3.new(0, 4, 0),
		Drag = 2,
		RotSpeed = NumberRange.new(-70, 70),
		Rotation = NumberRange.new(0, 360),
	})
	makeEmitter("smoke", {
		Lifetime = NumberRange.new(0.9, 1.7),
		Speed = NumberRange.new(2, 8),
		SpreadAngle = Vector2.new(70, 70),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 5) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(Color3.fromRGB(60, 56, 60)),
		Acceleration = Vector3.new(0, 3, 0),
		Drag = 2,
		RotSpeed = NumberRange.new(-50, 50),
		Rotation = NumberRange.new(0, 360),
	})
	makeEmitter("flame", {
		Lifetime = NumberRange.new(0.4, 0.9),
		Speed = NumberRange.new(6, 18),
		SpreadAngle = Vector2.new(40, 40),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2), NumberSequenceKeypoint.new(0.6, 1.4), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		LightEmission = 1,
		Acceleration = Vector3.new(0, 12, 0),
		Drag = 1.5,
		RotSpeed = NumberRange.new(-120, 120),
		Rotation = NumberRange.new(0, 360),
	})
	-- motes spawn on the surface of a sphere (the emitter part's size) and fall inward: "charging" and "implosion"
	makeEmitter("mote", {
		Lifetime = NumberRange.new(0.32, 0.5),
		Speed = NumberRange.new(10, 18),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.6) }),
		LightEmission = 1,
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		Brightness = 2,
	})
	makeEmitter("shard", {
		Lifetime = NumberRange.new(0.5, 1.0),
		Speed = NumberRange.new(14, 34),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
		LightEmission = 1,
		Drag = 3,
		Acceleration = Vector3.new(0, -14, 0),
		RotSpeed = NumberRange.new(-360, 360),
		Rotation = NumberRange.new(0, 360),
		Brightness = 2,
	})
	makeEmitter("soul", {
		Lifetime = NumberRange.new(1.0, 1.8),
		Speed = NumberRange.new(2, 8),
		SpreadAngle = Vector2.new(25, 25),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		LightEmission = 1,
		Acceleration = Vector3.new(0, 10, 0),
		Drag = 1,
		Brightness = 2,
	})
end

local function emitAt(kind: string, pos: Vector3, dir: Vector3?, color: Color3, count: number, extent: number?)
	local rec = emitters[kind]
	if not rec or count <= 0 then
		return
	end
	local d = if dir and dir.Magnitude > 0.01 then dir.Unit else UP
	rec.part.Size = Vector3.one * (extent or 0.4)
	rec.part.CFrame = CFrame.lookAt(pos, pos + d)
	rec.emitter.Color = ColorSequence.new(color)
	rec.emitter:Emit(math.max(1, math.floor(count * scale() + 0.5)))
end

local function rainbow(i: number): Color3
	return Color3.fromHSV((i * 0.17 + rng:NextNumber() * 0.1) % 1, 0.55, 1)
end

local function mine(userId: number): boolean
	return userId == LOCAL.UserId
end

local function nearLocal(pos: Vector3, range: number): boolean
	local char = LOCAL.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return hrp ~= nil and (hrp.Position - pos).Magnitude <= range
end

local function characterOf(userId: number): Model?
	local player = Players:GetPlayerByUserId(userId)
	return player and player.Character
end

local function rootOf(character: Model?): BasePart?
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function handOf(character: Model?, side: string): Vector3?
	local hand = character and (character:FindFirstChild(if side == "R" then "RightHand" else "LeftHand") :: BasePart?)
	if hand then
		return hand.Position
	end
	local hrp = rootOf(character)
	return if hrp then hrp.Position + hrp.CFrame.LookVector * 1.5 else nil
end

local function after(seconds: number, fn: () -> ())
	task.delay(seconds, function()
		local ok, err = pcall(function(): any
			return fn()
		end)
		if not ok then
			warn(`[ARMFORGE] ArmFx: {err}`)
		end
	end)
end

local function armColor(armId: string): Color3
	local arm = Arms.Defs[armId]
	return if arm then arm.palette.glow else WHITE
end

-- Impact layer per arm --------------------------------------------------------------------------------------------------------------

-- The arm's own flavour on top of the generic rock / creature impact: `dir` points from the target towards the attacker.
function ArmFx.impact(armId: string, pos: Vector3, dir: Vector3, power: number, crit: boolean)
	local arm = Arms.Defs[armId]
	if not arm then
		return
	end
	local glow = arm.palette.glow
	local d = if dir.Magnitude > 0.01 then dir.Unit else UP
	local big = power >= 1.2 or crit
	if armId == "Starter" then
		impactLines(pos, d, glow:Lerp(WHITE, 0.3), 5 + math.floor(power * 3), 2, 4.5 + power, 0.16, 0.16)
		if big then
			emitAt("shard", pos, d, Color3.fromRGB(255, 226, 150), 6)
		end
	elseif armId == "Stonebreaker" then
		EffectsController.ring(pos, d, Color3.fromRGB(190, 180, 170), 1.5, 7 + power * 3, 0.28)
		emitAt("smoke", pos, d, Color3.fromRGB(150, 142, 134), 2 + math.floor(power * 2))
		if big then
			groundLines(pos, Color3.fromRGB(70, 66, 62), 6, 3, 6 + power * 2, 0.16, 0.5)
		end
	elseif armId == "Alloy" then
		local n = 2 + math.floor(power * 1.5)
		for _ = 1, n do
			local rand = Vector3.new(rng:NextNumber() - 0.5, rng:NextNumber() - 0.5, rng:NextNumber() - 0.5)
			bolt(pos, pos + (d + rand * 2).Unit * (2.5 + rng:NextNumber() * 2.5), Color3.fromRGB(150, 226, 255), 0.14, 0.14, 3, 0.5)
		end
		emitAt("steam", pos, d, WHITE, 2 + math.floor(power * 2))
	elseif armId == "Crystal" then
		local n = 5 + math.floor(power * 3)
		for i = 1, n do
			emitAt("shard", pos, d, rainbow(i), 1)
		end
		for i = 1, 3 do
			local rand = Vector3.new(rng:NextNumber() - 0.5, rng:NextNumber() - 0.5, rng:NextNumber() - 0.5)
			streak(pos, pos + (d + rand * 1.8).Unit * (4 + rng:NextNumber() * 3), rainbow(i), 0.12, 0.2)
		end
	elseif armId == "Magma" then
		emitAt("flame", pos, d + UP * 0.6, Color3.fromRGB(255, 140, 40), 4 + math.floor(power * 3))
		EffectsController.emit("ember", pos, d + UP, Color3.fromRGB(255, 190, 80), 6 + math.floor(power * 4))
		EffectsController.ring(pos, d, Color3.fromRGB(255, 110, 30), 1.5, 8 + power * 3, 0.3)
	elseif armId == "Void" then
		emitAt("mote", pos, d, Color3.fromRGB(190, 120, 255), 8 + math.floor(power * 4), 5)
		local rand = Vector3.new(rng:NextNumber() - 0.5, rng:NextNumber() - 0.5, rng:NextNumber() - 0.5)
		local a = (d:Cross(rand))
		if a.Magnitude > 0.01 then
			local axis = a.Unit
			streak(pos - axis * (2.5 + power), pos + axis * (2.5 + power), Color3.fromRGB(226, 190, 255), 0.14, 0.22)
		end
	end
end

-- Swing arcs ---------------------------------------------------------------------------------------------------------------------

-- How each move cuts the air: "thrust" a straight line, "side" a flat crescent, "over" a vertical crescent, "up" a rising one,
-- "x" a diagonal rake, "wide" a two-handed spread.
local ARCS: { [string]: string } = {
	JabR = "thrust",
	JabL = "thrust",
	CrossR = "thrust",
	HookR = "side",
	HookL = "side",
	OverheadSlam = "over",
	SideSwingR = "side",
	SideSwingL = "side",
	GroundPound = "over",
	PistonR = "thrust",
	PistonL = "thrust",
	UppercutR = "up",
	UppercutL = "up",
	LungeR = "thrust",
	LungeL = "thrust",
	SpinThrustR = "side",
	VolcanoSlamR = "over",
	VolcanoSlamL = "over",
	MagmaDoubleSmash = "over",
	ClawRakeR = "x",
	ClawRakeL = "x",
	RendBoth = "wide",
	ChargedSmash = "over",
	ShatterWave = "over",
	BarrageFlurry = "thrust",
	PistonStorm = "thrust",
	QuakeStomp = "over",
	PrismLance = "thrust",
	EruptionSlam = "over",
	RiftTear = "wide",
}

-- A crescent of glowing segments in front of the character, drawn at the moment of contact.
function ArmFx.swingArc(character: Model, moveName: string, armId: string, power: number)
	local kind = ARCS[moveName]
	local hrp = rootOf(character)
	if not (kind and hrp) or not nearLocal(hrp.Position, 90) then
		return
	end
	local color = armColor(armId)
	local origin = hrp.Position + UP * 0.4
	local look = hrp.CFrame.LookVector
	local right = hrp.CFrame.RightVector
	local reach = 5.2 + power * 0.9
	local segments = math.max(3, math.floor(6 * scale() + 0.5))
	local function point(a: number): Vector3
		-- a: -1..1 across the sweep
		if kind == "side" then
			local ang = a * 1.05
			return origin + UP * 1.2 + (look * math.cos(ang) + right * math.sin(ang)) * reach
		elseif kind == "over" then
			local ang = a * 1.15
			return origin + (look * math.sin(ang + 0.3) * reach) + UP * (1.2 + math.cos(ang + 0.3) * reach * 0.9)
		elseif kind == "up" then
			local ang = a * 0.9
			return origin + look * (reach * 0.8) + right * 0.6 + UP * (1.3 + math.sin(ang) * reach * 0.9)
		elseif kind == "x" then
			return origin + look * (reach * 0.9) + right * (-a * reach * 0.55) + UP * (1.2 - a * reach * 0.5)
		elseif kind == "wide" then
			return origin + UP * 1.4 + look * (reach * 0.85) + right * (a * reach * 0.9)
		end
		return origin + UP * 1.4 + look * (1.5 + (a + 1) * 0.5 * reach)
	end
	local width = 0.22 + power * 0.1
	local life = 0.18 + power * 0.04
	for i = 1, segments do
		local a0 = -1 + 2 * (i - 1) / segments
		local a1 = -1 + 2 * i / segments
		after((i - 1) * 0.012, function()
			streak(point(a0), point(a1), color:Lerp(WHITE, 0.35), width, life)
		end)
	end
	if kind == "x" or kind == "wide" then
		-- a second, mirrored cut
		for i = 1, segments do
			local a0 = -1 + 2 * (i - 1) / segments
			local a1 = -1 + 2 * i / segments
			streak(point(-a0), point(-a1), color, width * 0.7, life)
		end
	end
end

-- Plays the arc of a move when its fist lands (`speed` is the animation speed the move plays at).
function ArmFx.swing(character: Model, moveName: string, armId: string, speed: number)
	local move = PoseMath.moves()[moveName]
	if not move then
		return
	end
	local delay = move.duration * move.contact / math.max(0.5, speed)
	after(delay, function()
		ArmFx.swingArc(character, moveName, armId, move.power)
	end)
end

-- Auras on characters -------------------------------------------------------------------------------------------------------------------

local auras: { [Model]: { [string]: Attachment } } = {}

-- A particle aura on a character for `seconds` (Overdrive flames, Critical Focus glints).
function ArmFx.aura(character: Model, kind: string, seconds: number, color: Color3)
	local hrp = rootOf(character)
	if not hrp or not nearLocal(hrp.Position, 130) then
		return
	end
	local held = auras[character]
	if held and held[kind] then
		held[kind]:Destroy()
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "ArmFxAura_" .. kind
	attachment.Parent = hrp
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.LockedToPart = false
	e.Lifetime = NumberRange.new(0.5, 0.9)
	if kind == "overdrive" then
		e.Rate = 34 * scale()
		e.Speed = NumberRange.new(2, 6)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Acceleration = Vector3.new(0, 9, 0)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
		e.Shape = Enum.ParticleEmitterShape.Cylinder
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	else
		e.Rate = 16 * scale()
		e.Speed = NumberRange.new(0.5, 2.5)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(0.5, 0.25), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		e.RotSpeed = NumberRange.new(-180, 180)
	end
	e.Parent = attachment
	local record = held or {}
	record[kind] = attachment
	auras[character] = record
	Debris:AddItem(attachment, seconds)
	after(seconds, function()
		if record[kind] == attachment then
			record[kind] = nil
		end
	end)
end

-- Skills ---------------------------------------------------------------------------------------------------------------------------------

-- Hand-held gathering: motes streaming into the fists while a move winds up.
local function charge(character: Model?, seconds: number, color: Color3, both: boolean)
	local steps = math.max(2, math.floor(seconds / 0.09))
	for i = 0, steps - 1 do
		after(i * 0.09, function()
			local r = handOf(character, "R")
			if r then
				emitAt("mote", r, UP, color, 3 + math.floor(i / steps * 4), 4 + i / steps * 2)
			end
			if both then
				local l = handOf(character, "L")
				if l then
					emitAt("mote", l, UP, color, 3 + math.floor(i / steps * 4), 4 + i / steps * 2)
				end
			end
		end)
	end
end

function ArmFx.skill(p: any)
	local color: Color3 = p.color or WHITE
	local character = characterOf(p.u)
	local hrp = rootOf(character)
	if not (character and hrp) then
		return
	end
	local isMine = mine(p.u)
	local floorPos = Vector3.new(hrp.Position.X, groundY(hrp.Position), hrp.Position.Z)
	if p.skill == "ChargedSmash" then
		-- the 0.9 s wind-up: orange motes pour into both fists and the ground ring contracts
		charge(character, 0.78, color, true)
		EffectsController.ring(floorPos, UP, color, 14, 3, 0.7)
		after(0.9, function()
			local pos = if p.tp then (p.tp :: Vector3) else hrp.Position + hrp.CFrame.LookVector * 6
			local y = groundY(pos)
			local ground = Vector3.new(pos.X, y, pos.Z)
			EffectsController.ring(ground, UP, color, 3, 22, 0.55)
			EffectsController.ring(ground, UP, WHITE, 2, 14, 0.4)
			groundLines(ground, color, 10, 5, 11, 0.22, 0.5)
			pillar(ground, color:Lerp(WHITE, 0.4), 3, 9, 0.35)
			emitAt("smoke", ground + UP, UP, Color3.fromRGB(150, 142, 134), 12)
			EffectsController.emit("chip", ground + UP, UP, color, 18)
			if isMine or nearLocal(ground, 70) then
				CameraController.shake(0.55, 0.3)
			end
		end)
	elseif p.skill == "Overdrive" then
		EffectsController.ring(floorPos, UP, color, 3, 16, 0.55)
		EffectsController.ring(floorPos, UP, Color3.fromRGB(255, 200, 120), 2, 11, 0.4)
		pillar(floorPos, color, 2.6, 12, 0.5)
		emitAt("flame", hrp.Position - UP * 1.5, UP, color, 22)
		ArmFx.aura(character, "overdrive", p.dur or 7, color)
		after((p.dur or 7), function()
			-- overheat: the arms vent smoke when the buff ends
			local r = rootOf(character)
			if r then
				emitAt("smoke", r.Position + UP, UP, Color3.fromRGB(110, 100, 100), 10)
				emitAt("steam", r.Position + UP * 2, UP, WHITE, 8)
			end
		end)
	elseif p.skill == "CriticalFocus" then
		EffectsController.ring(hrp.Position, UP, color, 12, 2.5, 0.5)
		after(0.25, function()
			local r = rootOf(character)
			if r then
				EffectsController.ring(r.Position, UP, WHITE, 9, 2, 0.4)
				EffectsController.flash(r.Position + UP * 2.2, color, 5, 0.3)
				emitAt("shard", r.Position + UP * 2, UP, color, 6)
			end
		end)
		ArmFx.aura(character, "focus", p.dur or 6, color)
	end
end

-- Shatter Wave: cracks race outward, a dust wall rolls and the ground heaves.
function ArmFx.wave(p: any)
	local pos: Vector3 = p.pos
	local color: Color3 = p.color or WHITE
	local radius: number = p.radius or 16
	local ground = Vector3.new(pos.X, groundY(pos), pos.Z)
	groundLines(ground, color, 16, radius * 0.5, radius * 0.95, 0.26, 0.6)
	for i = 1, 3 do
		after((i - 1) * 0.1, function()
			EffectsController.ring(ground + UP * 0.2, UP, if i == 2 then WHITE else color, 3, radius * (1.7 + i * 0.25), 0.5 + i * 0.1)
		end)
	end
	for i = 1, 8 do
		local a = (i / 8) * math.pi * 2
		emitAt("smoke", ground + Vector3.new(math.cos(a), 0.6, math.sin(a)) * radius * 0.55, UP, Color3.fromRGB(160, 150, 140), 3)
	end
	pillar(ground, color:Lerp(WHITE, 0.5), 2.4, 7, 0.3)
end

-- Signature moves ---------------------------------------------------------------------------------------------------------------------------

function ArmFx.signature(p: any)
	local def = Signatures.Defs[p.arm]
	local character = characterOf(p.u)
	local hrp = rootOf(character)
	if not (def and character and hrp) then
		return
	end
	local color = armColor(p.arm)
	local isMine = mine(p.u)
	local function target(): Vector3
		if p.tp then
			return p.tp :: Vector3
		end
		local r = rootOf(character) or hrp
		return r.Position + r.CFrame.LookVector * 7 + UP * 1.5
	end
	local function fromHand(side: string): Vector3
		return handOf(character, side) or hrp.Position
	end
	local function shake(amount: number, duration: number)
		if isMine or nearLocal(hrp.Position, 70) then
			CameraController.shake(amount, duration)
		end
	end
	local style = def.style
	if style == "barrage" then
		-- a knuckle-flash on each jab, then the haymaker's shock
		for i, strike in def.strikes do
			local last = i == #def.strikes
			after(strike.at, function()
				local t = target()
				local hand = fromHand(if i % 2 == 1 then "R" else "L")
				EffectsController.flash(hand, color, if last then 5 else 2.4, 0.12)
				if last then
					EffectsController.ring(t, (hrp.Position - t), color, 2, 15, 0.4)
					impactLines(t, (hrp.Position - t), Color3.fromRGB(255, 240, 190), 16, 4, 9, 0.24, 0.3)
					emitAt("shard", t, UP, Color3.fromRGB(255, 220, 140), 16)
					shake(0.6, 0.3)
					if isMine then
						EffectsController.floatText(t + UP * 3.5, "HAYMAKER!", color, 1.4, 3)
					end
				end
			end)
		end
	elseif style == "quake" then
		after(0.3, function()
			local r = rootOf(character)
			if r then
				emitAt("smoke", Vector3.new(r.Position.X, groundY(r.Position) + 0.4, r.Position.Z), UP, Color3.fromRGB(150, 142, 134), 5)
			end
		end)
		after(0.62, function()
			shake(0.95, 0.45)
			EffectsController.sound("Smash", hrp.Position, 1.1, 0.8)
		end)
	elseif style == "storm" then
		after(0.1, function()
			emitAt("steam", fromHand("R"), UP, WHITE, 5)
			emitAt("steam", fromHand("L"), UP, WHITE, 5)
		end)
		for i, strike in def.strikes do
			after(strike.at, function()
				local t = target()
				local hand = fromHand(if i % 2 == 1 then "R" else "L")
				bolt(hand, t, Color3.fromRGB(150, 226, 255), 0.18, 0.12, 3, 0.7)
				EffectsController.flash(hand, Color3.fromRGB(150, 226, 255), 1.8, 0.1)
			end)
		end
		after(1.05, function()
			local r = rootOf(character)
			if r then
				EffectsController.ring(r.Position, UP, Color3.fromRGB(150, 226, 255), 3, 14, 0.5)
				emitAt("steam", r.Position, UP, WHITE, 10)
				if isMine then
					EffectsController.floatText(r.Position + UP * 3.5, "OVERCLOCKED", Color3.fromRGB(150, 226, 255), 1.2, 3)
				end
			end
		end)
	elseif style == "lance" then
		charge(character, 0.55, color, false)
		after(0.7, function()
			local t = target()
			local from = fromHand("R")
			local dir = (t - from)
			local far = t + (if dir.Magnitude > 0.01 then dir.Unit else hrp.CFrame.LookVector) * 10
			for i = 1, 3 do
				local off = (hrp.CFrame.RightVector * (i - 2)) * 0.5
				streak(from + off, far + off * 2, rainbow(i), 0.5 - i * 0.08, 0.35)
			end
			EffectsController.flash(t, WHITE, 8, 0.2)
			EffectsController.ring(t, hrp.CFrame.LookVector, color, 2, 13, 0.4)
			for i = 1, 8 do
				emitAt("shard", t, UP, rainbow(i), 2)
			end
			shake(0.6, 0.3)
		end)
	elseif style == "eruption" then
		after(0.2, function()
			local r = rootOf(character)
			if r then
				emitAt("flame", Vector3.new(r.Position.X, groundY(r.Position) + 0.5, r.Position.Z), UP, Color3.fromRGB(255, 130, 30), 14)
			end
		end)
		after(0.46, function()
			local r = rootOf(character)
			if r then
				emitAt("flame", r.Position - UP * 1.4, -UP, Color3.fromRGB(255, 170, 60), 12)
			end
		end)
		after(0.66, function()
			local t = target()
			local ground = Vector3.new(t.X, groundY(t), t.Z)
			pillar(ground, Color3.fromRGB(205, 62, 12), 5, 22, 0.7)
			pillar(ground, Color3.fromRGB(255, 160, 60), 2, 26, 0.5)
			for i = 1, 3 do
				after(i * 0.07, function()
					EffectsController.ring(ground + UP * 0.2, UP, if i == 2 then Color3.fromRGB(255, 220, 140) else Color3.fromRGB(255, 100, 30), 3, 16 + i * 6, 0.55)
				end)
			end
			emitAt("flame", ground + UP, UP, Color3.fromRGB(255, 140, 40), 30)
			EffectsController.emit("ember", ground + UP * 3, UP, Color3.fromRGB(255, 200, 100), 40)
			emitAt("smoke", ground + UP * 4, UP, Color3.fromRGB(70, 60, 60), 10)
			groundLines(ground, Color3.fromRGB(255, 130, 40), 12, 5, 13, 0.3, 0.7)
			shake(1.0, 0.5)
			EffectsController.sound("Smash", ground, 1.2, 0.7)
		end)
	elseif style == "rift" then
		after(0.3, function()
			local t = target()
			emitAt("mote", t, UP, Color3.fromRGB(190, 120, 255), 12, 7)
			EffectsController.flash(t, Color3.fromRGB(120, 60, 200), 3, 0.4)
		end)
		after(0.5, function()
			local t = target()
			emitAt("mote", t, UP, Color3.fromRGB(190, 120, 255), 18, 9)
			EffectsController.flash(t, Color3.fromRGB(140, 80, 230), 6, 0.3)
		end)
		after(0.7, function()
			local t = target()
			local right = hrp.CFrame.RightVector
			local look = hrp.CFrame.LookVector
			streak(t - right * 7 + UP * 6, t + right * 7 - UP * 6, Color3.fromRGB(235, 205, 255), 0.5, 0.45)
			streak(t + right * 7 + UP * 6, t - right * 7 - UP * 6, Color3.fromRGB(150, 90, 255), 0.5, 0.45)
			streak(t - look * 0.2 + UP * 9, t - look * 0.2 - UP * 9, WHITE, 0.3, 0.3)
			EffectsController.flash(t, Color3.fromRGB(120, 60, 220), 12, 0.35)
			EffectsController.ring(t, look, Color3.fromRGB(190, 120, 255), 16, 2, 0.5)
			emitAt("shard", t, UP, Color3.fromRGB(210, 160, 255), 20)
			shake(0.8, 0.4)
		end)
	end
end

-- The area half of a signature (what actually got struck): rays, pillars and rings sized to the real radius.
function ArmFx.burst(p: any)
	local pos: Vector3 = p.pos
	local radius: number = p.radius or 12
	local style: string = p.style
	local arm = Signatures.Defs[p.arm]
	local color = armColor(p.arm)
	local ground = Vector3.new(pos.X, groundY(pos), pos.Z)
	if style == "quake" then
		groundLines(ground, Color3.fromRGB(80, 74, 68), 18, radius * 0.5, radius, 0.3, 0.8)
		for i = 1, 3 do
			after((i - 1) * 0.11, function()
				EffectsController.ring(ground + UP * 0.2, UP, if i == 2 then WHITE else Color3.fromRGB(200, 188, 170), 3, radius * (1.6 + i * 0.2), 0.55 + i * 0.1)
			end)
		end
		for i = 1, 10 do
			local a = (i / 10) * math.pi * 2
			emitAt("smoke", ground + Vector3.new(math.cos(a), 0.6, math.sin(a)) * radius * 0.6, UP, Color3.fromRGB(160, 150, 138), 3)
		end
		EffectsController.emit("chip", ground + UP, UP, Color3.fromRGB(150, 142, 134), 40)
		pillar(ground, Color3.fromRGB(230, 214, 190), 3, 8, 0.35)
	elseif style == "lance" then
		-- refracted rays fan out of the struck target
		for i = 1, 7 do
			local a = (i / 7) * math.pi * 2 + rng:NextNumber() * 0.3
			local dir = Vector3.new(math.cos(a), rng:NextNumber() * 0.5, math.sin(a)).Unit
			streak(pos, pos + dir * radius * 0.9, rainbow(i), 0.28, 0.35)
		end
		EffectsController.flash(pos, WHITE, 6, 0.25)
		EffectsController.ring(ground + UP * 0.2, UP, color, 2, radius * 1.6, 0.5)
		emitAt("shard", pos, UP, WHITE, 14)
	elseif style == "eruption" then
		for i = 1, 4 do
			local a = (i / 4) * math.pi * 2 + rng:NextNumber()
			local at = ground + Vector3.new(math.cos(a), 0, math.sin(a)) * radius * (0.45 + rng:NextNumber() * 0.4)
			after(i * 0.08, function()
				pillar(at, Color3.fromRGB(210, 70, 15), 2.6, 11 + rng:NextNumber() * 6, 0.5)
				emitAt("flame", at + UP, UP, Color3.fromRGB(255, 150, 50), 12)
				EffectsController.ring(at + UP * 0.2, UP, Color3.fromRGB(255, 110, 30), 1.5, 9, 0.4)
			end)
		end
		EffectsController.emit("ember", ground + UP * 2, UP, Color3.fromRGB(255, 190, 90), 36)
		groundLines(ground, Color3.fromRGB(255, 120, 30), 14, radius * 0.4, radius, 0.28, 0.8)
	elseif style == "rift" then
		-- the tear closes: a ring contracts onto the target and motes pour in
		EffectsController.ring(ground + UP * 0.3, UP, Color3.fromRGB(190, 120, 255), radius * 2.2, 2, 0.6)
		EffectsController.ring(pos, UP, Color3.fromRGB(235, 205, 255), radius * 1.4, 1, 0.45)
		emitAt("mote", pos, UP, Color3.fromRGB(190, 120, 255), 24, radius * 0.7)
		EffectsController.flash(pos, Color3.fromRGB(110, 50, 200), 8, 0.4)
	elseif arm then
		EffectsController.ring(ground + UP * 0.2, UP, color, 3, radius * 1.6, 0.5)
	end
	if nearLocal(pos, 80) then
		CameraController.shake(if style == "quake" or style == "eruption" then 0.7 else 0.4, 0.3)
	end
end

-- Creatures ---------------------------------------------------------------------------------------------------------------------------------

-- A creature attack landing: cracks, shock lines and a dust wall shaped like the attack that was telegraphed.
function ArmFx.creatureStrike(p: any)
	local origin: Vector3 = p.origin
	local dir: Vector3 = p.dir
	local color: Color3 = p.color or WHITE
	local boss = p.boss == true
	local ground = Vector3.new(origin.X, groundY(origin), origin.Z)
	if not nearLocal(origin, 110) then
		return
	end
	if p.shape == "circle" then
		local r: number = p.radius or 6
		groundLines(ground, color, if boss then 18 else 11, r * 0.45, r * 0.95, if boss then 0.34 else 0.22, 0.6)
		for i = 1, if boss then 6 else 4 do
			local a = (i / 6) * math.pi * 2
			emitAt("smoke", ground + Vector3.new(math.cos(a), 0.5, math.sin(a)) * r * 0.7, UP, Color3.fromRGB(150, 142, 134), 2)
		end
		pillar(ground, color:Lerp(WHITE, 0.35), r * 0.45, if boss then 12 else 7, 0.35)
	elseif p.shape == "line" then
		local length: number = p.length or 10
		local f = flat(dir)
		for i = 0, 5 do
			local d = length * (i / 5)
			after(i * 0.025, function()
				local at = ground + f * d
				pillar(at, color, 1.6, 4, 0.25)
				emitAt("smoke", at + UP * 0.5, UP, Color3.fromRGB(150, 142, 134), 2)
			end)
		end
		streak(ground + UP * 0.3, ground + UP * 0.3 + f * length, color:Lerp(WHITE, 0.4), 0.5, 0.25)
	else
		local length: number = p.length or 8
		local half: number = math.rad(p.halfAngle or 45)
		local f = flat(dir)
		for i = -2, 2 do
			local a = half * (i / 2)
			local d = (CFrame.fromAxisAngle(UP, -a) * f)
			streak(ground + UP * 0.8 + d * 1.5, ground + UP * 1.4 + d * length, color:Lerp(WHITE, 0.35), if boss then 0.45 else 0.3, 0.3)
		end
		emitAt("smoke", ground + f * length * 0.5 + UP * 0.6, UP, Color3.fromRGB(150, 142, 134), 5)
	end
	EffectsController.emit("spark", ground + UP * 0.5, UP, color, if boss then 30 else 14)
end

-- A creature falling: its light lifts out of the body and the ground sighs.
function ArmFx.creatureDefeat(p: any)
	local pos: Vector3 = p.pos
	local color: Color3 = p.color or WHITE
	local r: number = p.radius or 4
	local boss = p.boss == true
	local ground = Vector3.new(pos.X, groundY(pos), pos.Z)
	pillar(ground, color:Lerp(WHITE, 0.5), r * 0.6, if boss then 40 else 22, if boss then 1.2 else 0.8)
	pillar(ground, WHITE, r * 0.25, if boss then 46 else 26, if boss then 0.9 else 0.6)
	emitAt("soul", ground + UP * 2, UP, color:Lerp(WHITE, 0.3), if boss then 40 else 20)
	for i = 1, if boss then 4 else 2 do
		after(i * 0.12, function()
			EffectsController.ring(ground + UP * 0.3, UP, color, r, r * (4 + i * 2), 0.8)
		end)
	end
	groundLines(ground, color, if boss then 16 else 8, r * 0.8, r * 2.2, 0.26, 0.7)
	emitAt("shard", ground + UP * 3, UP, color:Lerp(WHITE, 0.4), if boss then 30 else 14)
end

-- A creature appearing: a column of light and a ring of motes pulled up out of the rock.
function ArmFx.creatureReveal(p: any)
	local pos: Vector3 = p.pos
	local color: Color3 = p.color or WHITE
	local ground = Vector3.new(pos.X, groundY(pos), pos.Z)
	pillar(ground, color, (p.radius or 4) * 0.5, if p.boss then 30 else 16, 0.6)
	emitAt("mote", ground + UP * 3, UP, color, 16, (p.radius or 4) * 2)
end

-- Magma burns what it hits: a short flame lick on a creature (or anything) at `pos`.
function ArmFx.burning(pos: Vector3, seconds: number)
	local n = math.max(2, math.floor(seconds * 2))
	for i = 0, n - 1 do
		after(i * 0.45, function()
			emitAt("flame", pos, UP, Color3.fromRGB(255, 140, 40), 4)
		end)
	end
end

-- Setup -----------------------------------------------------------------------------------------------------------------------------------------

function ArmFx.start()
	setupEmitters()
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local i = 1
		while i <= #active do
			local a = active[i]
			local k = (now - a.t0) / a.life
			if k >= 1 or not a.part.Parent then
				a.part.Parent = nil
				table.insert(pool[a.kind], a.part)
				active[i] = active[#active]
				active[#active] = nil
			else
				a.update(a.part, k)
				i += 1
			end
		end
	end)
end

return ArmFx
