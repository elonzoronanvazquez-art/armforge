--!strict
-- Everything the player SEES of the creatures released from rocks. The server owns all creature state and publishes it as model
-- attributes and Fx events; this controller only renders it:
--   * procedural animation (Motor6D.Transform on the joints CreatureBuilder created; nothing replicated, nothing uploaded)
--   * ground telegraphs for every attack (the area is locked on the server when the windup starts)
--   * overhead name / health / armor / core readout, a boss bar, the targeted rock's contents, and hit feedback
-- Nothing here decides damage, eligibility or rewards.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local CreatureConfig = require(Shared.Config.Creatures)
local SkillConfig = require(Shared.Config.Skills)
local Format = require(Shared.Util.Format)
local Store = require(script.Parent.Parent.Store)
local EffectsController = require(script.Parent.EffectsController)
local CameraController = require(script.Parent.CameraController)
local TargetController = require(script.Parent.TargetController)

local CreatureController = {}

local LOCAL = Players.LocalPlayer
local TAG = "ArmCreature"
local ANIM_RANGE = 170

type Joint = { motor: Motor6D, base: CFrame }
type Rig = {
	model: Model,
	joints: { [string]: Joint },
	spikes: { Joint },
	glowParts: { BasePart },
	plateParts: { { part: BasePart, color: Color3 } },
	core: BasePart?,
	lastPos: Vector3,
	speed: number,
	phase: number,
	def: CreatureConfig.CreatureDef?,
	billboard: BillboardGui?,
	highlight: Highlight?,
	labels: { name: TextLabel, hp: Frame, fill: Frame, status: TextLabel }?,
}

local rigs: { [Model]: Rig } = {}
local gui: ScreenGui
local bossBar: Frame
local bossRefs: { name: TextLabel, fill: Frame, status: TextLabel, phase: TextLabel }
local hurtFlash: Frame
local infoBoard: BillboardGui
local infoRefs: { title: TextLabel, sub: TextLabel, rec: TextLabel }
local overlay: Folder

local SOUND_FAMILY: { [string]: string } = { stone = "Stone", ore = "Metal", metal = "Metal", crystal = "Crystal", magma = "Magma" }

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function ease(x: number): number
	x = math.clamp(x, 0, 1)
	return 1 - (1 - x) ^ 3
end

local function nearLocal(pos: Vector3, range: number): boolean
	local char = LOCAL.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return hrp ~= nil and (hrp.Position - pos).Magnitude <= range
end

local function defOf(model: Model): CreatureConfig.CreatureDef?
	return CreatureConfig.Defs[model:GetAttribute("CreatureId") :: string]
end

-- Rig registration ---------------------------------------------------------------------------------------------------------------

local function buildBillboard(rig: Rig)
	local model, def = rig.model, rig.def
	local root = model.PrimaryPart
	if not (root and def) then
		return
	end
	local board = Instance.new("BillboardGui")
	board.Name = "CreatureInfo"
	board.Size = UDim2.fromOffset(190, 46)
	board.StudsOffsetWorldSpace = Vector3.new(0, (if model:GetAttribute("Rigged") == true then def.height else def.height * def.scale) + 3, 0)
	board.AlwaysOnTop = false
	board.LightInfluence = 0
	board.MaxDistance = 140
	board.Adornee = root
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 18)
	name.Font = Enum.Font.GothamBlack
	name.TextSize = 15
	name.TextColor3 = if def.tier == "boss" then Color3.fromRGB(255, 214, 120) elseif def.tier == "elite" then Color3.fromRGB(255, 160, 90) else Color3.fromRGB(255, 244, 232)
	name.Text = def.name
	name.Parent = board
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Color = Color3.fromRGB(20, 14, 10)
	stroke.Parent = name
	local hp = Instance.new("Frame")
	hp.Position = UDim2.fromOffset(15, 21)
	hp.Size = UDim2.new(1, -30, 0, 9)
	hp.BackgroundColor3 = Color3.fromRGB(30, 22, 20)
	hp.BorderSizePixel = 0
	hp.Parent = board
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = def.visual.glow
	fill.BorderSizePixel = 0
	fill.Parent = hp
	local status = Instance.new("TextLabel")
	status.BackgroundTransparency = 1
	status.Position = UDim2.fromOffset(0, 31)
	status.Size = UDim2.new(1, 0, 0, 14)
	status.Font = Enum.Font.GothamBold
	status.TextSize = 12
	status.TextColor3 = Color3.fromRGB(255, 244, 232)
	status.Text = ""
	status.Parent = board
	local stroke2 = Instance.new("UIStroke")
	stroke2.Thickness = 1.2
	stroke2.Color = Color3.fromRGB(20, 14, 10)
	stroke2.Parent = status
	board.Parent = root
	rig.billboard = board
	rig.labels = { name = name, hp = hp, fill = fill, status = status }
end

local function register(model: Model)
	if rigs[model] then
		return
	end
	local rig: Rig = {
		model = model,
		joints = {},
		spikes = {},
		glowParts = {},
		plateParts = {},
		core = nil,
		lastPos = if model.PrimaryPart then model.PrimaryPart.Position else Vector3.zero,
		speed = 0,
		phase = 0,
		def = defOf(model),
		billboard = nil,
		highlight = nil,
		labels = nil,
	}
	local function scan()
		table.clear(rig.joints)
		table.clear(rig.spikes)
		table.clear(rig.glowParts)
		table.clear(rig.plateParts)
		for _, d in model:GetDescendants() do
			if d:IsA("Motor6D") and string.sub(d.Name, 1, 2) == "J_" then
				local joint: Joint = { motor = d, base = CFrame.identity }
				rig.joints[string.sub(d.Name, 3)] = joint
				if string.sub(d.Name, 3, 7) == "Spike" then
					table.insert(rig.spikes, joint)
				end
			elseif d:IsA("BasePart") then
				if d.Name == "Core" then
					rig.core = d
				end
				if d:GetAttribute("Plate") then
					table.insert(rig.plateParts, { part = d, color = d.Color })
				end
				if d:GetAttribute("Glow") then
					table.insert(rig.glowParts, d)
				end
			end
		end
	end
	scan()
	model.DescendantAdded:Connect(function()
		task.defer(scan)
	end)
	rigs[model] = rig
	buildBillboard(rig)
end

local function unregister(model: Model)
	rigs[model] = nil
end

-- Animation ----------------------------------------------------------------------------------------------------------------------

local function setJoint(rig: Rig, name: string, cf: CFrame)
	local j = rig.joints[name]
	if j then
		j.motor.Transform = cf
	end
end

local function rot(x: number?, y: number?, z: number?): CFrame
	return CFrame.Angles(x or 0, y or 0, z or 0)
end

local function animate(rig: Rig, dt: number, now: number)
	local model = rig.model
	local root = model.PrimaryPart
	local def = rig.def
	if not (root and def) then
		return
	end
	-- movement speed from the replicated root
	local pos = root.Position
	local moved = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(rig.lastPos.X, 0, rig.lastPos.Z)).Magnitude
	rig.lastPos = pos
	rig.speed = rig.speed + (math.min(moved / math.max(dt, 1e-3), 30) - rig.speed) * math.min(1, dt * 8)
	local walking = math.clamp(rig.speed / 6, 0, 1)
	rig.phase += dt * (3 + rig.speed * 0.9)

	local state = (model:GetAttribute("State") :: string?) or "IDLE"
	local startT = (model:GetAttribute("StateStart") :: number?) or now
	local endT = (model:GetAttribute("StateEnd") :: number?) or now
	local span = math.max(0.05, endT - startT)
	local p = math.clamp((now - startT) / span, 0, 1)
	local kind = (model:GetAttribute("AttackKind") :: string?) or ""
	local t = os.clock()
	local arch = def.archetype
	-- procedural bodies are scaled by def.scale; an AI rig is already built at def.height, so its motions scale from the height
	local rigged = model:GetAttribute("Rigged") == true
	local unit = if rigged then def.height / 8 else def.scale
	local height = if rigged then def.height else def.height * unit

	local bob = math.sin(t * 2.2 + rig.phase * 0.1) * 0.12 * unit
	local lean = 0
	local sink = 0
	local armRaise = 0.15 + math.sin(t * 1.6) * 0.06 -- radians, forward/up
	local armSpread = 0
	local head = 0
	local sway = 0
	local spikeOut = 0
	local lunge = 0
	local rise = 0 -- the whole body rears up before a slam (creatures with a one-piece mesh have no arms to raise)
	if state == "EMERGING" then
		sink = -height * 1.1 * (1 - ease(p))
		lean = -0.4 * (1 - ease(p))
		armRaise = 2.4 * (1 - ease(p))
	elseif state == "WINDUP" then
		local e = ease(p)
		if kind == "circle" then
			armRaise = 0.2 + 2.6 * e
			lean = -0.3 * e
			rise = 0.9 * e * unit
		elseif kind == "cone" then
			armRaise = 0.2 + 1.2 * e
			sway = -1.1 * e
		else
			lean = -0.4 * e
			armRaise = 0.2 + 0.8 * e
			lunge = 0.5 * e
		end
		spikeOut = 0.9 * e
		head = -0.3 * e
	elseif state == "ATTACKING" then
		local e = ease(p)
		if kind == "circle" then
			armRaise = 2.8 - 2.6 * e
			lean = 0.45 * e
			rise = 0.9 * (1 - e) * unit
		elseif kind == "cone" then
			armRaise = 1.4 - 1.0 * e
			sway = -1.1 + 2.4 * e
		else
			lean = 0.5 * e
			lunge = -1.6 * e
		end
		spikeOut = -0.5 * e
	elseif state == "RECOVERING" then
		armRaise = 0.1
		lean = 0.3 * (1 - p * 0.5)
		sink = -0.15 * unit
		head = 0.4
	elseif state == "STAGGERED" then
		lean = -0.45
		armRaise = 0.5 + math.sin(t * 18) * 0.12
		head = -0.5
		sink = -0.1 * unit
	elseif state == "TRANSITION" then
		armSpread = 1.2 * math.sin(math.min(p, 1) * math.pi)
		armRaise = 1.2 * math.sin(math.min(p, 1) * math.pi)
		head = -0.6
	elseif state == "DEFEATED" then
		local e = ease(p)
		sink = -height * 0.45 * e
		lean = 0.7 * e
		armRaise = 0.1
		head = 0.8 * e
	end

	local gait = math.sin(rig.phase) * 0.55 * walking
	local gait2 = math.sin(rig.phase + math.pi) * 0.55 * walking

	setJoint(rig, "Body", CFrame.new(0, sink + rise + bob + (if arch == "shard" then math.sin(t * 1.7) * 0.35 * unit else 0), lunge * unit) * rot(-lean, if arch == "shard" then t * (0.6 + spikeOut) else 0, 0))
	setJoint(rig, "Head", rot(head, 0, 0))
	setJoint(rig, "ArmL", rot(armRaise + gait * 0.4, sway, armSpread))
	setJoint(rig, "ArmR", rot(armRaise + gait2 * 0.4, -sway, -armSpread))
	setJoint(rig, "LegL", rot(gait, 0, 0))
	setJoint(rig, "LegR", rot(gait2, 0, 0))
	setJoint(rig, "LegFL", rot(gait, 0, 0))
	setJoint(rig, "LegBR", rot(gait, 0, 0))
	setJoint(rig, "LegFR", rot(gait2, 0, 0))
	setJoint(rig, "LegBL", rot(gait2, 0, 0))
	setJoint(rig, "Tail", rot(0, math.sin(t * 3) * 0.35, 0))
	setJoint(rig, "Jaw", rot(if state == "WINDUP" then 0.6 * ease(p) else 0.1, 0, 0))
	for i, spike in rig.spikes do
		local dir = spike.motor.C0.Position
		local out = if dir.Magnitude > 0.01 then dir.Unit else Vector3.yAxis
		spike.motor.Transform = CFrame.new(out * (spikeOut * 1.4 + math.sin(t * 2 + i) * 0.12))
	end

	-- core + armor colouring: a bright pulsing core means "hit it now"; broken armor heats up
	local coreUntil = (model:GetAttribute("CoreUntil") :: number?) or 0
	local armorUntil = (model:GetAttribute("ArmorUntil") :: number?) or 0
	local coreOpen = coreUntil > now
	local armorOpen = armorUntil > now
	local glow = def.visual.glow
	if rig.core then
		if coreOpen then
			rig.core.Color = glow:Lerp(Color3.new(1, 1, 1), 0.55 + 0.45 * math.sin(t * 14))
		else
			rig.core.Color = glow:Lerp(Color3.new(0, 0, 0), if def.armor then 0.35 else 0.1)
		end
	end
	for _, entry in rig.plateParts do
		entry.part.Color = if armorOpen then entry.color:Lerp(glow, 0.5) else entry.color
	end
	-- Textured AI meshes cannot be tinted through Color, so the state cue is a fill highlight: a pulsing gold glow while the core is
	-- exposed, a steady ember glow while the armor is broken.
	if coreOpen or armorOpen then
		local h: Highlight
		local existing = rig.highlight
		if existing then
			h = existing
		else
			local fresh = Instance.new("Highlight")
			fresh.Name = "ArmforgeCreatureState"
			fresh.OutlineTransparency = 1
			fresh.DepthMode = Enum.HighlightDepthMode.Occluded
			fresh.Parent = model
			rig.highlight = fresh
			h = fresh
		end
		h.Enabled = true
		if coreOpen then
			h.FillColor = Color3.fromRGB(255, 226, 120)
			h.FillTransparency = 0.45 + 0.2 * math.sin(t * 14)
		else
			h.FillColor = glow
			h.FillTransparency = 0.72
		end
	elseif rig.highlight then
		rig.highlight.Enabled = false
	end
end

-- Overhead readout -------------------------------------------------------------------------------------------------------------

local function skillName(id: string): string
	local d = SkillConfig.Defs[id]
	return if d then d.name else id
end

local function statusText(model: Model, def: CreatureConfig.CreatureDef, now: number): (string, Color3)
	local state = (model:GetAttribute("State") :: string?) or ""
	local coreUntil = (model:GetAttribute("CoreUntil") :: number?) or 0
	local armored = model:GetAttribute("Armored") == true
	if state == "EMERGING" then
		return "EMERGING...", Color3.fromRGB(255, 244, 232)
	elseif state == "DEFEATED" then
		return "DEFEATED", Color3.fromRGB(150, 255, 150)
	elseif coreUntil > now then
		return "CORE EXPOSED! x" .. tostring(def.core and def.core.mult or 1), Color3.fromRGB(255, 232, 120)
	elseif state == "WINDUP" then
		local attack = (model:GetAttribute("Attack") :: string?) or ""
		for _, a in def.attacks do
			if a.id == attack then
				return (if a.interruptible then "INTERRUPT: " else "") .. a.name .. "!", if a.interruptible then Color3.fromRGB(120, 230, 255) else Color3.fromRGB(255, 130, 100)
			end
		end
		return "ATTACK!", Color3.fromRGB(255, 130, 100)
	elseif state == "TRANSITION" then
		return "ENRAGED", Color3.fromRGB(255, 130, 100)
	elseif armored and def.armor then
		local names = {}
		for _, s in def.armor.breakers do
			table.insert(names, skillName(s))
		end
		return "ARMORED - " .. table.concat(names, " / "), Color3.fromRGB(190, 200, 215)
	elseif ((model:GetAttribute("ArmorUntil") :: number?) or 0) > now then
		return "ARMOR BROKEN", Color3.fromRGB(255, 190, 110)
	end
	return "", Color3.new(1, 1, 1)
end

local function refreshReadouts(now: number)
	local hrp = (LOCAL.Character and LOCAL.Character:FindFirstChild("HumanoidRootPart")) :: BasePart?
	local boss: Model? = nil
	local bossDist = 160
	for model, rig in rigs do
		local def = rig.def
		local root = model.PrimaryPart
		if def and root then
			local hp: number = (model:GetAttribute("Hp") :: number?) or 0
			local maxHp: number = (model:GetAttribute("MaxHp") :: number?) or 1
			local labels = rig.labels
			if labels then
				labels.fill.Size = UDim2.fromScale(math.clamp(hp / maxHp, 0, 1), 1)
				local text, color = statusText(model, def, now)
				labels.status.Text = text
				labels.status.TextColor3 = color
			end
			if def.tier == "boss" and hrp then
				local d = (root.Position - hrp.Position).Magnitude
				if d < bossDist and model:GetAttribute("State") ~= "DEFEATED" then
					boss, bossDist = model, d
				end
			end
		end
	end
	if boss then
		local def = defOf(boss)
		if def then
			local hp: number = (boss:GetAttribute("Hp") :: number?) or 0
			local maxHp: number = (boss:GetAttribute("MaxHp") :: number?) or 1
			bossBar.Visible = true
			bossRefs.name.Text = string.upper(def.name)
			bossRefs.fill.Size = UDim2.fromScale(math.clamp(hp / maxHp, 0, 1), 1)
			local text, color = statusText(boss, def, now)
			bossRefs.status.Text = text
			bossRefs.status.TextColor3 = color
			local phases = if def.phases then #def.phases + 1 else 1
			bossRefs.phase.Text = `PHASE {boss:GetAttribute("Phase") or 1} / {phases}      {Format.compact(hp)} / {Format.compact(maxHp)}`
		end
	else
		bossBar.Visible = false
	end
end

-- Sealed-rock information ------------------------------------------------------------------------------------------------------

local function skulls(n: number): string
	return string.rep("*", n) .. string.rep("-", 5 - n)
end

-- The board hangs on a small invisible anchor part that is moved above whichever rock is targeted (the same arrangement as a
-- creature's overhead readout, which renders reliably).
local infoAnchor: Part? = nil

local function makeInfoBoard()
	local holder: Part
	local existing = infoAnchor
	if existing and existing.Parent ~= nil then
		holder = existing
	else
		local fresh = Instance.new("Part")
		fresh.Name = "RockInfoAnchor"
		fresh.Anchored = true
		fresh.CanCollide = false
		fresh.CanQuery = false
		fresh.CanTouch = false
		fresh.CastShadow = false
		fresh.Transparency = 1
		fresh.Size = Vector3.new(1, 1, 1)
		fresh.Parent = overlay
		infoAnchor = fresh
		holder = fresh
	end
	infoBoard = Instance.new("BillboardGui")
	infoBoard.Name = "RockContents"
	infoBoard.Size = UDim2.fromOffset(250, 70)
	infoBoard.AlwaysOnTop = false
	infoBoard.LightInfluence = 0
	infoBoard.MaxDistance = 90
	infoBoard.Enabled = false
	infoBoard.Adornee = holder
	infoBoard.Parent = holder
	local function line(y: number, h: number, size: number, font: Enum.Font): TextLabel
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromOffset(0, y)
		l.Size = UDim2.new(1, 0, 0, h)
		l.Font = font
		l.TextSize = size
		l.TextWrapped = true
		l.TextColor3 = Color3.fromRGB(255, 244, 232)
		l.Text = ""
		l.Parent = infoBoard
		local st = Instance.new("UIStroke")
		st.Thickness = 1.5
		st.Color = Color3.fromRGB(20, 14, 10)
		st.Parent = l
		return l
	end
	infoRefs = { title = line(0, 20, 16, Enum.Font.GothamBlack), sub = line(20, 16, 12, Enum.Font.GothamBold), rec = line(36, 34, 11, Enum.Font.Gotham) }
end

local function refreshInfo(target: Model?)
	local holder = infoAnchor
	if infoBoard.Parent == nil or not holder or holder.Parent == nil then
		makeInfoBoard()
		holder = infoAnchor
	end
	if not target or not target.Parent or target:GetAttribute("Contains") == nil or target:GetAttribute("CreatureId") ~= nil then
		infoBoard.Enabled = false
		return
	end
	local d = Store.data
	local height: number = (target:GetAttribute("Height") :: number?) or 5
	local anchor = target.PrimaryPart
	if not anchor then
		infoBoard.Enabled = false
		return
	end
	if holder then
		holder.Position = anchor.Position + Vector3.new(0, height * 0.55 + 5, 0)
	end
	local tier = target:GetAttribute("Tier") :: string
	local rebirths: number = (target:GetAttribute("GuardianRebirths") :: number?) or 0
	local contains = target:GetAttribute("Contains") :: string
	infoRefs.title.Text = if tier == "boss" then `SEALED: {contains}` else `Contains: {contains}`
	infoRefs.title.TextColor3 = if tier == "boss" then Color3.fromRGB(255, 214, 120) elseif tier == "elite" then Color3.fromRGB(255, 160, 90) else Color3.fromRGB(255, 244, 232)
	infoRefs.sub.Text = `Danger {skulls((target:GetAttribute("Danger") :: number?) or 1)}   {string.upper(tier)}`
	if tier == "boss" and d and d.rebirths < rebirths then
		infoRefs.rec.Text = `The seal will not open: needs Rebirth {rebirths} (you have {d.rebirths})`
		infoRefs.rec.TextColor3 = Color3.fromRGB(255, 120, 100)
	else
		infoRefs.rec.Text = (target:GetAttribute("Recommended") :: string?) or ""
		infoRefs.rec.TextColor3 = Color3.fromRGB(190, 200, 215)
	end
	infoBoard.Enabled = true
end

-- Telegraphs -------------------------------------------------------------------------------------------------------------------

local function flatPart(size: Vector3, cf: CFrame, color: Color3, transparency: number, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency
	p.Size = size
	p.CFrame = cf
	if shape then
		p.Shape = shape
	end
	p.Parent = overlay
	return p
end

local function groundAt(pos: Vector3): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { overlay, LOCAL.Character :: Instance }
	local hit = workspace:Raycast(pos + Vector3.new(0, 12, 0), Vector3.new(0, -40, 0), params)
	return if hit then hit.Position.Y + 0.15 else pos.Y + 0.15
end

local function telegraph(p: any)
	local danger = if p.boss then Color3.fromRGB(255, 60, 40) else Color3.fromRGB(255, 120, 60)
	local edge = if p.interruptible then Color3.fromRGB(120, 230, 255) else danger
	local origin: Vector3 = p.origin
	local dir: Vector3 = p.dir
	local y = groundAt(origin)
	local base = Vector3.new(origin.X, y, origin.Z)
	local parts: { Part } = {}
	local fills: { (number) -> () } = {}
	if p.shape == "circle" then
		local d = (p.radius or 5) * 2
		local rim = flatPart(Vector3.new(0.18, d, d), CFrame.new(base) * rot(0, 0, math.pi / 2), edge, 0.55, Enum.PartType.Cylinder)
		local fill = flatPart(Vector3.new(0.2, 0.1, 0.1), CFrame.new(base + Vector3.new(0, 0.05, 0)) * rot(0, 0, math.pi / 2), danger, 0.45, Enum.PartType.Cylinder)
		table.insert(parts, rim)
		table.insert(parts, fill)
		table.insert(fills, function(k: number)
			local s = math.max(0.1, d * k)
			fill.Size = Vector3.new(0.2, s, s)
		end)
	elseif p.shape == "line" then
		local length: number = p.length or 10
		local width: number = p.width or 3
		local look = CFrame.lookAt(base, base + Vector3.new(dir.X, 0, dir.Z))
		local rim = flatPart(Vector3.new(width, 0.18, length), look * CFrame.new(0, 0, -length / 2), edge, 0.55)
		local fill = flatPart(Vector3.new(width * 0.92, 0.2, 0.1), look * CFrame.new(0, 0.05, -0.05), danger, 0.45)
		table.insert(parts, rim)
		table.insert(parts, fill)
		table.insert(fills, function(k: number)
			local len = math.max(0.1, length * k)
			fill.Size = Vector3.new(width * 0.92, 0.2, len)
			fill.CFrame = look * CFrame.new(0, 0.05, -len / 2)
		end)
	else
		local length: number = p.length or 8
		local half = math.rad(p.halfAngle or 45)
		local slices = 9
		local sliceWidth = 2 * length * math.tan(half / slices) * 1.15
		local fillSlices: { Part } = {}
		for i = 0, slices - 1 do
			local a = -half + (i + 0.5) / slices * 2 * half
			local look = CFrame.lookAt(base, base + Vector3.new(dir.X, 0, dir.Z)) * rot(0, -a, 0)
			table.insert(parts, flatPart(Vector3.new(sliceWidth, 0.18, length), look * CFrame.new(0, 0, -length / 2), edge, 0.62))
			local f = flatPart(Vector3.new(sliceWidth, 0.2, 0.1), look * CFrame.new(0, 0.05, -0.05), danger, 0.5)
			table.insert(parts, f)
			table.insert(fillSlices, f)
			f:SetAttribute("Angle", a)
		end
		table.insert(fills, function(k: number)
			local len = math.max(0.1, length * k)
			for _, f in fillSlices do
				local a = f:GetAttribute("Angle") :: number
				local look = CFrame.lookAt(base, base + Vector3.new(dir.X, 0, dir.Z)) * rot(0, -a, 0)
				f.Size = Vector3.new(sliceWidth, 0.2, len)
				f.CFrame = look * CFrame.new(0, 0.05, -len / 2)
			end
		end)
	end
	local duration: number = math.max(0.2, p.dur)
	local started: number = p.serverT
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function()
		local k = (serverNow() - started) / duration
		if k >= 1.05 or #parts == 0 then
			conn:Disconnect()
			for _, part in parts do
				part:Destroy()
			end
			return
		end
		for _, f in fills do
			f(math.clamp(k, 0, 1))
		end
		local pulse = 0.4 + 0.1 * math.sin(os.clock() * 24)
		for _, part in parts do
			if part.Transparency < 0.6 then
				part.Transparency = pulse + 0.08
			end
		end
	end)
	if p.interruptible and nearLocal(origin, 60) then
		EffectsController.floatText(origin + Vector3.new(0, 6, 0), "INTERRUPT!", Color3.fromRGB(120, 230, 255), 1.1, 3)
	end
end

-- Fx handlers (dispatched from EffectsController) ---------------------------------------------------------------------------------

local function soundKey(prefix: string, family: string?): string
	return prefix .. (SOUND_FAMILY[family or "stone"] or "Stone")
end

local function familyOf(creatureId: string): string
	local def = CreatureConfig.Defs[creatureId]
	return if def then def.family else "stone"
end

function CreatureController.reveal(p: any)
	local pos: Vector3 = p.pos
	local color: Color3 = p.color
	local boss = p.boss == true
	local scale: number = p.radius or 4
	EffectsController.flash(pos + Vector3.new(0, 2, 0), color, scale * 3, 0.5)
	EffectsController.ring(Vector3.new(pos.X, pos.Y + 0.4, pos.Z), Vector3.yAxis, color, scale, scale * (if boss then 9 else 5), if boss then 0.9 else 0.6)
	EffectsController.emit("dust", pos + Vector3.new(0, 1, 0), Vector3.yAxis, Color3.fromRGB(190, 180, 170), if boss then 40 else 20)
	EffectsController.emit("spark", pos + Vector3.new(0, 2, 0), Vector3.yAxis, color, if boss then 40 else 22)
	EffectsController.sound(soundKey("Break", familyOf(p.def)), pos, if boss then 1.3 else 1, if boss then 0.7 else 0.9)
	if nearLocal(pos, 130) then
		CameraController.shake(if boss then 0.7 else 0.35, if boss then 0.9 else 0.45)
		if boss or p.tier == "elite" then
			local Notifications = require(script.Parent.Parent.UI.Notifications)
			Notifications.toast(if boss then `GUARDIAN: {p.name} - {p.title}` else `{p.name} bursts out!`, if boss then "warn" else "good")
		end
	end
end

function CreatureController.engage(p: any)
	if p.boss and nearLocal(p.pos, 120) then
		EffectsController.sound("Crit", p.pos, 1.2, 0.6)
	end
end

function CreatureController.telegraph(p: any)
	if not nearLocal(p.origin, 220) then
		return
	end
	telegraph(p)
end

function CreatureController.strike(p: any)
	local pos: Vector3 = p.pos
	local origin: Vector3 = p.origin
	EffectsController.ring(Vector3.new(origin.X, origin.Y + 0.4, origin.Z), Vector3.yAxis, p.color, 2, if p.shape == "circle" then 14 else 8, 0.4)
	EffectsController.emit("dust", origin + Vector3.new(0, 0.6, 0), Vector3.yAxis, Color3.fromRGB(190, 180, 170), if p.boss then 24 else 12)
	EffectsController.sound("BreakStone", origin, if p.boss then 1.2 else 0.85, if p.boss then 0.75 else 1)
	if nearLocal(pos, 90) then
		CameraController.shake(if p.boss then 0.5 else 0.25, 0.25)
	end
end

function CreatureController.hit(p: any)
	local pos: Vector3 = p.pos
	local color: Color3 = p.color
	local isMine = p.attacker == LOCAL.UserId
	EffectsController.flash(pos, if p.crit then Color3.fromRGB(255, 240, 180) else color:Lerp(Color3.new(1, 1, 1), 0.5), 3 + (p.power or 1) * 2, 0.14)
	EffectsController.emit("spark", pos, Vector3.yAxis, color, if p.coreHit then 26 else 12)
	EffectsController.sound(soundKey("Hit", if p.armored then "ore" else "stone"), pos, 0.9, if p.armored then 0.8 else 1)
	for model in rigs do
		if model:GetAttribute("RockId") == p.id then
			EffectsController.hitFlash(model, if p.coreHit then Color3.fromRGB(255, 236, 140) else Color3.new(1, 1, 1))
		end
	end
	if isMine then
		CameraController.shake(0.12 + (p.power or 1) * 0.12 + (if p.coreHit or p.interrupted then 0.2 else 0))
	end
	if (isMine or nearLocal(pos, 60)) and p.dmg > 0 then
		local text = EffectsController.formatNumber(p.dmg)
		local tint = Color3.fromRGB(255, 244, 232)
		local scale = 1
		if p.coreHit then
			text = "CORE " .. text
			tint = Color3.fromRGB(255, 220, 90)
			scale = 1.5
		elseif p.armored then
			text = text .. " (armor)"
			tint = Color3.fromRGB(170, 180, 195)
			scale = 0.9
		elseif p.crit then
			text = "CRIT " .. text
			tint = Color3.fromRGB(255, 220, 90)
			scale = 1.3
		end
		EffectsController.floatText(pos + Vector3.new(0, 1.5, 0), text, tint, scale)
		if p.armorBroken then
			EffectsController.floatText(pos + Vector3.new(0, 4.5, 0), "ARMOR BROKEN!", Color3.fromRGB(255, 180, 90), 1.4, 4)
			EffectsController.ring(Vector3.new(pos.X, pos.Y, pos.Z), Vector3.yAxis, Color3.fromRGB(255, 180, 90), 3, 14, 0.4)
		end
		if p.interrupted then
			EffectsController.floatText(pos + Vector3.new(0, 6.5, 0), "INTERRUPTED!", Color3.fromRGB(120, 230, 255), 1.5, 4)
			EffectsController.ring(Vector3.new(pos.X, pos.Y, pos.Z), Vector3.yAxis, Color3.fromRGB(120, 230, 255), 3, 16, 0.45)
		end
	end
end

function CreatureController.phase(p: any)
	local pos: Vector3 = p.pos
	EffectsController.ring(Vector3.new(pos.X, pos.Y + 0.5, pos.Z), Vector3.yAxis, p.color, 4, 40, 0.8)
	EffectsController.flash(pos + Vector3.new(0, 6, 0), p.color, 14, 0.5)
	EffectsController.sound("BreakStone", pos, 1.3, 0.6)
	if nearLocal(pos, 140) then
		CameraController.shake(0.6, 0.8)
		local Notifications = require(script.Parent.Parent.UI.Notifications)
		Notifications.toast(p.text, "warn")
	end
end

function CreatureController.defeat(p: any)
	local pos: Vector3 = p.pos
	local color: Color3 = p.color
	local r: number = p.radius or 4
	EffectsController.flash(pos + Vector3.new(0, 3, 0), color, r * 4, 0.5)
	EffectsController.ring(Vector3.new(pos.X, pos.Y + 0.4, pos.Z), Vector3.yAxis, color, r, r * (if p.boss then 10 else 6), 0.7)
	EffectsController.emit("dust", pos + Vector3.new(0, 2, 0), Vector3.yAxis, Color3.fromRGB(190, 180, 170), if p.boss then 50 else 26)
	EffectsController.emit("spark", pos + Vector3.new(0, 3, 0), Vector3.yAxis, color, 40)
	EffectsController.sound("LevelUp", pos, if p.boss then 1.2 else 0.8, if p.boss then 0.7 else 1.1)
	if nearLocal(pos, 130) then
		CameraController.shake(if p.boss then 0.8 else 0.4, if p.boss then 1.0 else 0.5)
	end
end

function CreatureController.retreat(p: any)
	local pos: Vector3 = p.pos
	EffectsController.emit("dust", pos + Vector3.new(0, 1, 0), Vector3.yAxis, Color3.fromRGB(190, 180, 170), 20)
	EffectsController.ring(Vector3.new(pos.X, pos.Y + 0.4, pos.Z), Vector3.yAxis, p.color, 2, 10, 0.5)
end

function CreatureController.hurt(p: any)
	hurtFlash.BackgroundTransparency = math.clamp(0.8 - p.dmg / 80, 0.3, 0.75)
	TweenService:Create(hurtFlash, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
	CameraController.shake(math.clamp(p.dmg / 60, 0.15, 0.6), 0.25)
end

-- Setup --------------------------------------------------------------------------------------------------------------------------

local function buildUi()
	gui = Instance.new("ScreenGui")
	gui.Name = "ArmforgeCreatureUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 6
	gui.Parent = LOCAL:WaitForChild("PlayerGui")

	hurtFlash = Instance.new("Frame")
	hurtFlash.Size = UDim2.fromScale(1, 1)
	hurtFlash.BackgroundColor3 = Color3.fromRGB(200, 20, 20)
	hurtFlash.BackgroundTransparency = 1
	hurtFlash.BorderSizePixel = 0
	hurtFlash.Active = false
	hurtFlash.Parent = gui

	bossBar = Instance.new("Frame")
	bossBar.Name = "BossBar"
	bossBar.AnchorPoint = Vector2.new(0.5, 0)
	bossBar.Position = UDim2.new(0.5, 0, 0, 14)
	bossBar.Size = UDim2.fromOffset(460, 62)
	bossBar.BackgroundColor3 = Color3.fromRGB(24, 18, 16)
	bossBar.BackgroundTransparency = 0.15
	bossBar.BorderSizePixel = 0
	bossBar.Visible = false
	bossBar.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = bossBar
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 190, 90)
	stroke.Thickness = 2
	stroke.Parent = bossBar
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromOffset(12, 4)
	name.Size = UDim2.new(1, -24, 0, 20)
	name.Font = Enum.Font.GothamBlack
	name.TextSize = 17
	name.TextColor3 = Color3.fromRGB(255, 214, 120)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Text = ""
	name.Parent = bossBar
	local back = Instance.new("Frame")
	back.Position = UDim2.fromOffset(12, 28)
	back.Size = UDim2.new(1, -24, 0, 12)
	back.BackgroundColor3 = Color3.fromRGB(46, 34, 30)
	back.BorderSizePixel = 0
	back.Parent = bossBar
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(255, 120, 60)
	fill.BorderSizePixel = 0
	fill.Parent = back
	local status = Instance.new("TextLabel")
	status.BackgroundTransparency = 1
	status.Position = UDim2.fromOffset(12, 43)
	status.Size = UDim2.new(0.6, 0, 0, 16)
	status.Font = Enum.Font.GothamBold
	status.TextSize = 13
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextColor3 = Color3.new(1, 1, 1)
	status.Text = ""
	status.Parent = bossBar
	local phase = Instance.new("TextLabel")
	phase.BackgroundTransparency = 1
	phase.Position = UDim2.new(0.5, 0, 0, 43)
	phase.Size = UDim2.new(0.5, -12, 0, 16)
	phase.Font = Enum.Font.GothamBold
	phase.TextSize = 12
	phase.TextXAlignment = Enum.TextXAlignment.Right
	phase.TextColor3 = Color3.fromRGB(190, 200, 215)
	phase.Text = ""
	phase.Parent = bossBar
	bossRefs = { name = name, fill = fill, status = status, phase = phase }

	makeInfoBoard()
end

function CreatureController.start()
	overlay = Instance.new("Folder")
	overlay.Name = "ArmforgeTelegraphs"
	overlay.Parent = workspace
	buildUi()

	for _, inst in CollectionService:GetTagged(TAG) do
		register(inst :: Model)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(inst)
		task.defer(register, inst :: Model)
	end)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(inst)
		unregister(inst :: Model)
	end)

	TargetController.changed:connect(function(target)
		refreshInfo(target)
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		local now = serverNow()
		local hrp = (LOCAL.Character and LOCAL.Character:FindFirstChild("HumanoidRootPart")) :: BasePart?
		for model, rig in rigs do
			local root = model.PrimaryPart
			if root and (not hrp or (root.Position - hrp.Position).Magnitude <= ANIM_RANGE) then
				animate(rig, dt, now)
			end
		end
		acc += dt
		if acc >= 0.1 then
			acc = 0
			refreshReadouts(now)
			refreshInfo(TargetController.current)
		end
	end)
end

return CreatureController
