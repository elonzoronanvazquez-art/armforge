--!strict
-- Client-side effects for everything the server announces over the Fx remote: impact flashes, sparks, dust, debris,
-- shockwaves, damage numbers, rock jiggle, skill pulses and layered audio. All of it is cosmetic and budgeted:
--   * debris is simulated by hand (no physics) from a capped pool,
--   * particle emitters are persistent "anchor" parts that are moved and Emit()ed (no per-hit instances),
--   * sounds and damage numbers are capped per Config/Game.Budgets,
--   * reduce-effects in settings cuts counts further.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local SoundService = game:GetService("SoundService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local Net = require(Shared.Net)
local Game = require(Shared.Config.Game)
local Assets = require(Shared.Config.Assets)
local Rocks = require(Shared.Config.Rocks)
local Store = require(script.Parent.Parent.Store)
local ArmAnimator = require(script.Parent.ArmAnimator)
local CameraController = require(script.Parent.CameraController)

local EffectsController = {}

local LOCAL = Players.LocalPlayer
local fxFolder: Folder
local rng = Random.new()

-- Settings helpers --------------------------------------------------------------------------------------------------

local function settings(): any
	return (Store.data and Store.data.settings) or { sfx = 1, reduceFx = false, damageNumbers = true }
end

local function countScale(): number
	return if settings().reduceFx then 0.4 else 1
end

local function nearLocal(pos: Vector3, range: number): boolean
	local char = LOCAL.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return hrp ~= nil and (hrp.Position - pos).Magnitude <= range
end

-- Audio ---------------------------------------------------------------------------------------------------------------

local activeSounds = 0
local soundAnchors: { Part } = {}

local function newAnchor(): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Name = "SoundAnchor"
	return p
end

local function soundAnchor(): Part
	local p: Part? = table.remove(soundAnchors)
	return p or newAnchor()
end

-- Plays one of the sounds registered under `key` (Config/Assets.Sounds) at a world position.
function EffectsController.sound(key: string, pos: Vector3?, volumeScale: number?, pitchScale: number?)
	local list = Assets.Sounds[key]
	if not list or activeSounds >= Game.Budgets.soundsMax then
		return
	end
	local vol = settings().sfx
	if vol <= 0.01 then
		return
	end
	local def = list[rng:NextInteger(1, #list)]
	local sound = Instance.new("Sound")
	sound.SoundId = def.id
	sound.Volume = def.volume * (volumeScale or 1) * vol
	sound.PlaybackSpeed = (def.pitch[1] + (def.pitch[2] - def.pitch[1]) * rng:NextNumber()) * (pitchScale or 1)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 14
	sound.RollOffMaxDistance = 130
	local anchor: Part? = nil
	if pos then
		local a = soundAnchor()
		a.CFrame = CFrame.new(pos)
		a.Parent = fxFolder
		sound.Parent = a
		anchor = a
	else
		sound.Parent = SoundService
	end
	if def.start then
		sound.TimePosition = def.start
	end
	activeSounds += 1
	sound:Play()
	local life = def.length or 1.5
	task.delay(life, function()
		activeSounds -= 1
		sound:Stop()
		sound:Destroy()
		if anchor then
			anchor.Parent = nil
			table.insert(soundAnchors, anchor)
		end
	end)
end

-- Particle emitters ------------------------------------------------------------------------------------------------------

type EmitterKind = "spark" | "chip" | "dust" | "ember" | "star"

local emitters: { [string]: { part: Part, emitter: ParticleEmitter } } = {}

local function makeEmitter(kind: string, props: { [string]: any })
	local part = Instance.new("Part")
	part.Name = "Emitter_" .. kind
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.4, 0.4, 0.4)
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.EmissionDirection = Enum.NormalId.Front
	e.LockedToPart = false
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = part
	part.Parent = fxFolder
	emitters[kind] = { part = part, emitter = e }
end

local function emit(kind: string, pos: Vector3, dir: Vector3, color: Color3, count: number)
	local rec = emitters[kind]
	if not rec or count <= 0 then
		return
	end
	local d = if dir.Magnitude > 0.01 then dir.Unit else Vector3.yAxis
	rec.part.CFrame = CFrame.lookAt(pos, pos + d)
	rec.emitter.Color = ColorSequence.new(color)
	rec.emitter:Emit(math.max(1, math.floor(count * countScale() + 0.5)))
end

local function setupEmitters()
	makeEmitter("spark", {
		Lifetime = NumberRange.new(0.18, 0.45),
		Speed = NumberRange.new(16, 34),
		SpreadAngle = Vector2.new(65, 65),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.42), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
		LightEmission = 1,
		Drag = 2.5,
		Acceleration = Vector3.new(0, -48, 0),
		Brightness = 2,
	})
	makeEmitter("chip", {
		Lifetime = NumberRange.new(0.5, 0.95),
		Speed = NumberRange.new(10, 24),
		SpreadAngle = Vector2.new(75, 75),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.34), NumberSequenceKeypoint.new(1, 0.12) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0), NumberSequenceKeypoint.new(1, 1) }),
		Acceleration = Vector3.new(0, -70, 0),
		RotSpeed = NumberRange.new(-420, 420),
		Rotation = NumberRange.new(0, 360),
	})
	makeEmitter("dust", {
		Lifetime = NumberRange.new(0.7, 1.4),
		Speed = NumberRange.new(3, 9),
		SpreadAngle = Vector2.new(80, 80),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 4.2) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }),
		Acceleration = Vector3.new(0, 2.5, 0),
		Drag = 2,
		RotSpeed = NumberRange.new(-60, 60),
		Rotation = NumberRange.new(0, 360),
	})
	makeEmitter("ember", {
		Lifetime = NumberRange.new(0.9, 1.8),
		Speed = NumberRange.new(5, 14),
		SpreadAngle = Vector2.new(60, 60),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.34), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
		LightEmission = 1,
		Acceleration = Vector3.new(0, 9, 0),
		Drag = 1.2,
	})
	makeEmitter("star", {
		Lifetime = NumberRange.new(0.6, 1.3),
		Speed = NumberRange.new(4, 14),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(0.5, 0.3), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
		LightEmission = 1,
		RotSpeed = NumberRange.new(-180, 180),
		Brightness = 2,
	})
end

-- Transient visuals (flash balls, rings): manual animation ----------------------------------------------------------------

type Anim = { part: Part, t0: number, life: number, update: (Part, number) -> (), done: (Part) -> () }

local anims: { Anim } = {}
local freeBalls: { Part } = {}
local freeRings: { Part } = {}
local lightsActive = 0

local function newFxPart(name: string, shape: Enum.PartType): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Material = Enum.Material.Neon
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Name = name
	return p
end

local function getBall(): Part
	local p: Part? = table.remove(freeBalls)
	return p or newFxPart("FxBall", Enum.PartType.Ball)
end

local function getRing(): Part
	local p: Part? = table.remove(freeRings)
	return p or newFxPart("FxRing", Enum.PartType.Cylinder)
end

local function flash(pos: Vector3, color: Color3, size: number, life: number)
	local ball = getBall()
	ball.Color = color
	ball.Transparency = 0.1
	ball.Size = Vector3.new(size * 0.4, size * 0.4, size * 0.4)
	ball.CFrame = CFrame.new(pos)
	ball.Parent = fxFolder
	local light: PointLight? = nil
	if lightsActive < Game.Budgets.impactLightsMax and not settings().reduceFx then
		lightsActive += 1
		local l = Instance.new("PointLight")
		l.Color = color
		l.Range = 14 + size * 3
		l.Brightness = 3
		l.Shadows = false
		l.Parent = ball
		light = l
	end
	table.insert(anims, {
		part = ball,
		t0 = os.clock(),
		life = life,
		update = function(p: Part, k: number)
			local s = size * (0.4 + 1.1 * (1 - (1 - k) ^ 2))
			p.Size = Vector3.new(s, s, s)
			p.Transparency = 0.1 + 0.9 * k
			if light then
				light.Brightness = 3 * (1 - k)
			end
		end,
		done = function(p: Part)
			if light then
				light:Destroy()
				lightsActive -= 1
			end
			p.Parent = nil
			table.insert(freeBalls, p)
		end,
	})
end

-- A flat expanding ring facing `normal`.
local function ring(pos: Vector3, normal: Vector3, color: Color3, startSize: number, endSize: number, life: number)
	local r = getRing()
	r.Color = color
	r.Transparency = 0.25
	r.Size = Vector3.new(0.18, startSize, startSize)
	local n = if normal.Magnitude > 0.01 then normal.Unit else Vector3.yAxis
	r.CFrame = CFrame.lookAt(pos, pos + n) * CFrame.Angles(0, math.pi / 2, 0)
	r.Parent = fxFolder
	table.insert(anims, {
		part = r,
		t0 = os.clock(),
		life = life,
		update = function(p: Part, k: number)
			local s = startSize + (endSize - startSize) * (1 - (1 - k) ^ 3)
			p.Size = Vector3.new(0.18 * (1 - k * 0.6), s, s)
			p.Transparency = 0.25 + 0.75 * k
		end,
		done = function(p: Part)
			p.Parent = nil
			table.insert(freeRings, p)
		end,
	})
end

-- Debris (manual ballistic simulation) -----------------------------------------------------------------------------------

type Debris = { part: Part, vel: Vector3, spin: Vector3, born: number, life: number, floorY: number, size: Vector3, bounces: number }

local debris: { Debris } = {}
local freeDebris: { Part } = {}
local GRAVITY = Vector3.new(0, -78, 0)

local function spawnDebris(pos: Vector3, vel: Vector3, size: Vector3, color: Color3, material: Enum.Material, floorY: number, life: number)
	if #debris >= Game.Budgets.debrisMax then
		return
	end
	local part: Part? = table.remove(freeDebris)
	if not part then
		local created = Instance.new("Part")
		created.Anchored = true
		created.CanCollide = false
		created.CanQuery = false
		created.CanTouch = false
		created.CastShadow = false
		created.TopSurface = Enum.SurfaceType.Smooth
		created.BottomSurface = Enum.SurfaceType.Smooth
		created.Name = "Debris"
		part = created
	end
	local debrisPart = part :: Part
	debrisPart.Color = color
	debrisPart.Material = material
	debrisPart.Size = size
	debrisPart.Transparency = 0
	debrisPart.CFrame = CFrame.new(pos) * CFrame.Angles(rng:NextNumber() * 6, rng:NextNumber() * 6, rng:NextNumber() * 6)
	debrisPart.Parent = fxFolder
	table.insert(debris, {
		part = debrisPart,
		vel = vel,
		spin = Vector3.new(rng:NextNumber() - 0.5, rng:NextNumber() - 0.5, rng:NextNumber() - 0.5) * 16,
		born = os.clock(),
		life = life,
		floorY = floorY,
		size = size,
		bounces = 0,
	})
end

local function stepDebris(dt: number)
	local now = os.clock()
	local i = 1
	while i <= #debris do
		local d = debris[i]
		local age = now - d.born
		if age >= d.life then
			d.part.Parent = nil
			table.insert(freeDebris, d.part)
			debris[i] = debris[#debris]
			debris[#debris] = nil
		else
			d.vel += GRAVITY * dt
			local cf = d.part.CFrame
			local pos = cf.Position + d.vel * dt
			if pos.Y < d.floorY + d.size.Y * 0.35 then
				pos = Vector3.new(pos.X, d.floorY + d.size.Y * 0.35, pos.Z)
				if d.bounces < 2 and d.vel.Y < -4 then
					d.vel = Vector3.new(d.vel.X * 0.55, -d.vel.Y * 0.32, d.vel.Z * 0.55)
					d.bounces += 1
				else
					d.vel = Vector3.new(d.vel.X * 0.8, 0, d.vel.Z * 0.8)
					d.spin *= 0.5
				end
			end
			d.part.CFrame = CFrame.new(pos) * (cf - cf.Position) * CFrame.Angles(d.spin.X * dt, d.spin.Y * dt, d.spin.Z * dt)
			local remaining = d.life - age
			if remaining < 0.4 then
				local k = remaining / 0.4
				d.part.Size = d.size * math.max(0.05, k)
			end
			i += 1
		end
	end
end

-- Damage numbers -------------------------------------------------------------------------------------------------------------

local numberPool: { BillboardGui } = {}
local numbersActive = 0

local function formatNumber(n: number): string
	if n >= 1e9 then
		return string.format("%.1fB", n / 1e9)
	elseif n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif n >= 1e4 then
		return string.format("%.1fK", n / 1e3)
	end
	return tostring(math.floor(n + 0.5))
end
EffectsController.formatNumber = formatNumber

local function floatText(pos: Vector3, text: string, color: Color3, scale: number, rise: number?)
	if numbersActive >= Game.Budgets.damageNumbersMax then
		return
	end
	local g: BillboardGui? = table.remove(numberPool)
	if not g then
		local created = Instance.new("BillboardGui")
		created.Size = UDim2.fromOffset(160, 48)
		created.AlwaysOnTop = true
		created.LightInfluence = 0
		created.MaxDistance = 140
		local label = Instance.new("TextLabel")
		label.Name = "L"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.Parent = created
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Color3.fromRGB(20, 16, 24)
		stroke.Parent = label
		g = created
	end
	local g2 = g :: BillboardGui
	local anchor = soundAnchor()
	anchor.CFrame = CFrame.new(pos)
	anchor.Parent = fxFolder
	g2.Adornee = anchor
	g2.Size = UDim2.fromOffset(160 * scale, 48 * scale)
	local label = g2:FindFirstChild("L") :: TextLabel
	label.Text = text
	label.TextColor3 = color
	label.TextTransparency = 0
	label.TextStrokeTransparency = 1
	local labelStroke = label:FindFirstChildOfClass("UIStroke") :: UIStroke
	labelStroke.Transparency = 0
	g2.StudsOffsetWorldSpace = Vector3.new((rng:NextNumber() - 0.5) * 2, 1, (rng:NextNumber() - 0.5) * 2)
	g2.Parent = anchor
	numbersActive += 1
	local t0 = os.clock()
	local life = 0.85
	local riseBy = rise or 4
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function()
		local k = (os.clock() - t0) / life
		if k >= 1 then
			conn:Disconnect()
			numbersActive -= 1
			g2.Parent = nil
			(g2 :: any).Adornee = nil
			anchor.Parent = nil
			table.insert(soundAnchors, anchor)
			table.insert(numberPool, g2)
			return
		end
		g2.StudsOffsetWorldSpace = g2.StudsOffsetWorldSpace:Lerp(Vector3.new(0, 1 + riseBy * (1 - (1 - k) ^ 2), 0), 0.25)
		local fade = math.clamp((k - 0.55) / 0.45, 0, 1)
		label.TextTransparency = fade
		labelStroke.Transparency = fade
	end)
end
EffectsController.floatText = floatText

-- Rock jiggle + hit flash ----------------------------------------------------------------------------------------------------

type Jiggle = { model: Model, base: CFrame, dir: Vector3, amp: number, t0: number, life: number }
local jiggles: { [Model]: Jiggle } = {}
local flashHighlight: Highlight

local function jiggle(model: Model, dir: Vector3, amp: number)
	local existing = jiggles[model]
	if existing then
		existing.amp = math.max(existing.amp * 0.6, amp)
		existing.dir = dir
		existing.t0 = os.clock()
		return
	end
	jiggles[model] = { model = model, base = model:GetPivot(), dir = dir, amp = amp, t0 = os.clock(), life = 0.2 }
end

local function stepJiggles()
	local now = os.clock()
	for model, j in jiggles do
		if not model.Parent then
			jiggles[model] = nil
		else
			local k = (now - j.t0) / j.life
			if k >= 1 then
				model:PivotTo(j.base)
				jiggles[model] = nil
			else
				local decay = (1 - k) ^ 2
				local wob = math.sin(k * math.pi * 7)
				model:PivotTo(j.base * CFrame.new(j.dir * j.amp * decay * wob))
			end
		end
	end
end

local function hitFlash(model: Model, color: Color3)
	flashHighlight.Adornee = model
	flashHighlight.Enabled = true
	flashHighlight.FillColor = color
	flashHighlight.FillTransparency = 0.35
	local tween = TweenService:Create(flashHighlight, TweenInfo.new(0.16), { FillTransparency = 1 })
	tween.Completed:Connect(function()
		if flashHighlight.FillTransparency >= 0.99 then
			flashHighlight.Enabled = false
		end
	end)
	tween:Play()
end

-- Event handlers ------------------------------------------------------------------------------------------------------------

local function rockDef(id: string): Rocks.RockDef
	return Rocks.Defs[id] or Rocks.Defs.Granite
end

local function soundKey(prefix: string, def: Rocks.RockDef): string
	local key = prefix .. def.sound
	if Assets.Sounds[key] then
		return key
	end
	return prefix .. "Stone"
end

local function materialOf(value: number): Enum.Material
	local ok, mat = pcall(function()
		return Enum.Material:FromValue(value)
	end)
	return if ok and mat then mat else Enum.Material.Slate
end

local function spawnChunkDebris(chunks: { any }, pos: Vector3, dir: Vector3, strength: number, floorY: number, perChunk: number)
	for _, info in chunks do
		for _ = 1, perChunk do
			local size = (info.s :: Vector3) * (0.32 + rng:NextNumber() * 0.28)
			local outward = (info.p :: Vector3) - pos
			local spread = Vector3.new(rng:NextNumber() - 0.5, rng:NextNumber() * 0.6, rng:NextNumber() - 0.5)
			local vel = (dir * (8 + rng:NextNumber() * 10) + outward.Unit * 5 + spread * 14) * strength + Vector3.new(0, 10 + rng:NextNumber() * 12, 0)
			spawnDebris(
				info.p + (spread * 0.6),
				vel,
				Vector3.new(math.max(0.25, size.X), math.max(0.22, size.Y), math.max(0.25, size.Z)),
				info.c,
				materialOf(info.m),
				floorY,
				1.1 + rng:NextNumber() * 0.9
			)
		end
	end
end

local function onHit(p: any)
	local def = rockDef(p.def)
	local pos: Vector3 = p.pos
	local dir: Vector3 = p.dir
	local power: number = p.power or 1
	local color: Color3 = p.trail or def.colors.glow
	local model = nil :: Model?
	for _, inst in CollectionService:GetTagged("ArmRock") do
		if inst:GetAttribute("RockId") == p.id then
			model = inst :: Model
			break
		end
	end
	local modelHeight: number = (if model then (model:GetAttribute("Height") :: number?) else nil) or 5
	local floorY = (if model then model:GetPivot().Position.Y - modelHeight * 0.45 else pos.Y - 2)
	local isMine = p.attacker == LOCAL.UserId
	local near = nearLocal(pos, 80)

	if p.quiet then
		spawnChunkDebris(p.chunks, pos, dir, 0.7, floorY, 1)
		emit("chip", pos, dir, def.colors.mid, 4)
		return
	end

	-- impact: flash, sparks, chips, dust
	flash(pos, if p.crit then Color3.fromRGB(255, 240, 180) else color:Lerp(Color3.new(1, 1, 1), 0.5), 3 + power * 2.4, 0.14)
	emit("spark", pos, dir, color:Lerp(Color3.new(1, 1, 1), 0.35), (10 + power * 10) * (if p.crit then 1.6 else 1))
	emit("chip", pos, dir, def.colors.shell:Lerp(def.colors.mid, 0.4), 6 + power * 6)
	emit("dust", pos, dir, def.colors.shell:Lerp(Color3.fromRGB(200, 190, 180), 0.55), 3 + power * 4)
	if def.family == "magma" or def.family == "crystal" then
		emit(if def.family == "magma" then "ember" else "star", pos, dir, def.colors.glow, 4 + power * 4)
	end
	spawnChunkDebris(p.chunks, pos, dir, 0.9 + power * 0.3, floorY, 2)
	ring(pos, dir, color, 1.5, 6 + power * 4, 0.3)
	if p.crit then
		ring(pos, dir, Color3.fromRGB(255, 232, 150), 2, 11, 0.36)
		EffectsController.sound("Crit", pos, 1)
	end
	if p.finisher or p.rend or p.skill then
		ring(pos, Vector3.yAxis, color, 3, 14 + power * 4, 0.45)
	end
	EffectsController.sound(soundKey("Hit", def), pos, 0.9 + power * 0.25, 1)
	if p.stageChanged and p.stage ~= "COLLAPSE" then
		EffectsController.sound(soundKey("Hit", def), pos, 1.2, 0.7)
		emit("dust", pos, Vector3.yAxis, def.colors.shell, 8)
		if model then
			CameraController.shake(0.25, 0.2)
		end
	end
	if model then
		jiggle(model, -dir, 0.18 + 0.12 * power)
		hitFlash(model, if p.crit then Color3.fromRGB(255, 244, 200) else Color3.new(1, 1, 1))
	end

	-- the attacker feels the hit
	if isMine then
		local shake = 0.12 + 0.28 * power + (if p.crit then 0.12 else 0)
		CameraController.shake(shake)
		local char = LOCAL.Character
		if char then
			local stop = if p.skill then 0.1 elseif p.finisher or p.rend then 0.07 else 0.035
			ArmAnimator.hitStop(char, stop)
		end
	elseif near then
		CameraController.shake(0.05 * power, 0.1)
	end

	-- damage number
	if settings().damageNumbers and (isMine or near) and p.dmg > 0 then
		local big = p.crit or p.rend or p.finisher or p.skill ~= nil
		floatText(pos + Vector3.new(0, 1.5, 0), (if p.crit then "CRIT " else "") .. formatNumber(p.dmg), if p.crit then Color3.fromRGB(255, 220, 90) elseif p.rend then Color3.fromRGB(200, 140, 255) else Color3.fromRGB(255, 244, 232), if big then 1.35 else 1)
	end
end

local function onBreak(p: any)
	local def = rockDef(p.def)
	local pos: Vector3 = p.pos
	local floorY = pos.Y - (p.height or 5) * 0.45
	local radius: number = p.radius or 4
	local isKiller = p.killer == LOCAL.UserId
	local near = nearLocal(pos, 110)

	flash(pos, def.colors.glow, radius * 2.4, 0.3)
	ring(Vector3.new(pos.X, floorY + 0.4, pos.Z), Vector3.yAxis, def.colors.glow, radius * 1.2, radius * 7, 0.55)
	ring(Vector3.new(pos.X, floorY + 0.4, pos.Z), Vector3.yAxis, Color3.new(1, 1, 1), radius, radius * 5, 0.4)
	emit("dust", pos, Vector3.yAxis, def.colors.shell:Lerp(Color3.fromRGB(200, 190, 180), 0.5), 22)
	emit("dust", Vector3.new(pos.X, floorY + 0.5, pos.Z), Vector3.yAxis, def.colors.mid, 14)
	emit("spark", pos, Vector3.yAxis, def.colors.glow, 36)
	emit("chip", pos, Vector3.yAxis, def.colors.shell, 24)
	emit(if def.family == "magma" then "ember" elseif def.family == "crystal" then "star" else "spark", pos, Vector3.yAxis, def.colors.glow, 24)
	spawnChunkDebris(p.chunks, pos, Vector3.yAxis, 1.3, floorY, 2)
	EffectsController.sound(soundKey("Break", def), pos, 1.1, 1)
	if near then
		CameraController.shake(if isKiller then 0.65 else 0.35, 0.34)
	end
end

local function onSpawn(p: any)
	local def = rockDef(p.def)
	local pos: Vector3 = p.pos
	local floorY = pos.Y - 4
	emit("star", Vector3.new(pos.X, floorY + 1, pos.Z), Vector3.yAxis, def.colors.glow, 10)
	emit("dust", Vector3.new(pos.X, floorY + 0.6, pos.Z), Vector3.yAxis, def.colors.shell, 8)
	ring(Vector3.new(pos.X, floorY + 0.3, pos.Z), Vector3.yAxis, def.colors.glow, 2, (p.radius or 4) * 3, 0.5)
	if nearLocal(pos, 70) then
		EffectsController.sound("Spawn", pos, 0.8, 1)
	end
end

local function characterOf(userId: number): Model?
	local player = Players:GetPlayerByUserId(userId)
	return player and player.Character
end

local function onSwing(p: any)
	if p.u == LOCAL.UserId then
		return -- the local player already animated this strike on input
	end
	local char = characterOf(p.u)
	if char then
		ArmAnimator.play(char, p.move, p.speed)
		local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			EffectsController.sound("Swing", hrp.Position, 0.6, 1)
		end
	end
end

local function onSkill(p: any)
	local color: Color3 = p.color or Color3.new(1, 1, 1)
	local char = characterOf(p.u)
	if char and p.u ~= LOCAL.UserId then
		ArmAnimator.play(char, p.move, 1)
	end
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		local pos = hrp.Position - Vector3.new(0, 2.6, 0)
		ring(pos, Vector3.yAxis, color, 3, 14, 0.5)
		emit("star", hrp.Position, Vector3.yAxis, color, 16)
		EffectsController.sound("Smash", hrp.Position, 0.45, 1.4)
		if p.skill == "Overdrive" then
			emit("ember", hrp.Position, Vector3.yAxis, color, 30)
		end
	end
end

local function onWave(p: any)
	local pos: Vector3 = p.pos
	local color: Color3 = p.color or Color3.new(1, 1, 1)
	local floor = pos - Vector3.new(0, 2.6, 0)
	ring(floor, Vector3.yAxis, color, 4, p.radius * 2.1, 0.55)
	ring(floor, Vector3.yAxis, Color3.new(1, 1, 1), 2, p.radius * 1.5, 0.4)
	emit("dust", floor + Vector3.new(0, 1, 0), Vector3.yAxis, Color3.fromRGB(200, 190, 180), 26)
	EffectsController.sound("Smash", pos, 1, 0.9)
	if nearLocal(pos, 100) then
		CameraController.shake(0.7, 0.4)
	end
end

local function onTravel(p: any)
	local pos: Vector3 = p.pos
	local color: Color3 = p.color or Color3.new(1, 1, 1)
	flash(pos, color, 12, 0.5)
	ring(pos - Vector3.new(0, 2.5, 0), Vector3.yAxis, color, 3, 20, 0.6)
	emit("star", pos, Vector3.yAxis, color, 40)
	EffectsController.sound("Spawn", pos, 1.2, 0.7)
end

local function onRebirth(p: any)
	local pos: Vector3 = p.pos
	local color = Color3.fromRGB(205, 140, 255)
	flash(pos, color, 24, 0.9)
	for i = 1, 4 do
		task.delay(i * 0.12, function()
			ring(pos - Vector3.new(0, 2.5, 0), Vector3.yAxis, color, 4, 30 + i * 12, 0.8)
		end)
	end
	emit("star", pos, Vector3.yAxis, color, 80)
	emit("spark", pos, Vector3.yAxis, Color3.fromRGB(255, 220, 160), 60)
	EffectsController.sound("Rebirth", pos, 1.2, 1)
	if nearLocal(pos, 150) then
		CameraController.shake(0.8, 0.9)
	end
end

-- helpers shared with CreatureController (same budgets, same pooled visuals)
EffectsController.flash = flash
EffectsController.ring = ring
EffectsController.emit = emit
EffectsController.hitFlash = hitFlash

local function creatureFx(name: string): (any) -> ()
	return function(p: any)
		-- required lazily: CreatureController itself requires this module
		local controller = require(script.Parent.CreatureController) :: any
		controller[name](p)
	end
end

local dispatch: { [string]: (any) -> () } = {
	Reveal = creatureFx("reveal"),
	Engage = creatureFx("engage"),
	Telegraph = creatureFx("telegraph"),
	CreatureStrike = creatureFx("strike"),
	CreatureHit = creatureFx("hit"),
	PhaseChange = creatureFx("phase"),
	CreatureDefeat = creatureFx("defeat"),
	Retreat = creatureFx("retreat"),
	Hurt = creatureFx("hurt"),
	Hit = onHit,
	Break = onBreak,
	Spawn = onSpawn,
	Swing = onSwing,
	Skill = onSkill,
	Wave = onWave,
	Travel = onTravel,
	Rebirth = onRebirth,
}

-- Rocks pop in when they respawn ---------------------------------------------------------------------------------------------

local function popIn(model: Model)
	if model:GetAttribute("Generation") and (model:GetAttribute("Generation") :: number) <= 1 then
		return -- first life: already there when we arrived
	end
	task.defer(function()
		local ok = pcall(function()
			model:ScaleTo(0.35)
		end)
		if not ok then
			return
		end
		local t0 = os.clock()
		local conn: RBXScriptConnection
		conn = RunService.Heartbeat:Connect(function()
			if not model.Parent then
				conn:Disconnect()
				return
			end
			local k = math.clamp((os.clock() - t0) / 0.45, 0, 1)
			local s = 0.35 + 0.65 * (1 - (1 - k) ^ 3) + math.sin(k * math.pi) * 0.12
			pcall(function()
				model:ScaleTo(if k >= 1 then 1 else s)
			end)
			if k >= 1 then
				conn:Disconnect()
			end
		end)
	end)
end

function EffectsController.start()
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "ArmforgeFx"
	fxFolder.Parent = workspace
	flashHighlight = Instance.new("Highlight")
	flashHighlight.Name = "ArmforgeHitFlash"
	flashHighlight.FillTransparency = 1
	flashHighlight.OutlineTransparency = 1
	flashHighlight.DepthMode = Enum.HighlightDepthMode.Occluded
	flashHighlight.Enabled = false
	local holder = Instance.new("Folder")
	holder.Name = "ArmforgeFlashHolder"
	holder.Parent = workspace
	flashHighlight.Parent = holder
	setupEmitters()

	local remotes = Net.client()
	remotes.Fx.OnClientEvent:Connect(function(kind: string, payload: any)
		local handler = dispatch[kind]
		if handler then
			local ok, err = pcall(function(): any
				return handler(payload)
			end)
			if not ok then
				warn(`[ARMFORGE] fx {kind}: {err}`)
			end
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		-- animated transients
		local now = os.clock()
		local i = 1
		while i <= #anims do
			local a = anims[i]
			local k = (now - a.t0) / a.life
			if k >= 1 then
				a.done(a.part)
				anims[i] = anims[#anims]
				anims[#anims] = nil
			else
				a.update(a.part, k)
				i += 1
			end
		end
		stepDebris(math.min(dt, 0.05))
		stepJiggles()
	end)

	CollectionService:GetInstanceAddedSignal("ArmRock"):Connect(function(inst)
		if inst:IsA("Model") then
			popIn(inst)
		end
	end)
end

return EffectsController
