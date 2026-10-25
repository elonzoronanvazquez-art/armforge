--!strict
-- Procedural attack animation for every visible character. Moves are keyframed poses (shared/Config/Animations,
-- evaluated by shared/Logic/PoseMath) layered on top of the default walk/idle animation by writing joint Transforms
-- AFTER the Animator has run (RunService.Stepped) and restoring them BEFORE it runs (PreAnimation). Both joint kinds
-- (AnimationConstraint, Motor6D) are supported; this place's R15 avatars use AnimationConstraints.
-- Purely presentational: nothing here decides gameplay.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local PoseMath = require(Shared.Logic.PoseMath)
local ArmBuilder = require(Shared.Runtime.ArmBuilder)

local ArmAnimator = {}

type Joint = Motor6D | AnimationConstraint

type Clip = {
	move: PoseMath.Move,
	start: number,
	speed: number,
	pausedAt: number?,
	pauseUntil: number,
	pausedTotal: number,
	trails: { Trail },
}

type Rig = {
	character: Model,
	joints: { [string]: Joint? },
	base: { [Joint]: CFrame },
	written: { [Joint]: CFrame },
	clip: Clip?,
	weight: number,
}

local JOINT_NAMES: { [string]: string } = {
	Root = "Root",
	Waist = "Waist",
	Neck = "Neck",
	RShoulder = "RightShoulder",
	RElbow = "RightElbow",
	LShoulder = "LeftShoulder",
	LElbow = "LeftElbow",
	RHip = "RightHip",
	LHip = "LeftHip",
	RKnee = "RightKnee",
	LKnee = "LeftKnee",
}

local rigs: { [Model]: Rig } = {}

local function setTransform(joint: Joint, value: CFrame)
	if joint:IsA("Motor6D") then
		joint.Transform = value
	else
		(joint :: AnimationConstraint).Transform = value
	end
end

local function findJoints(character: Model): { [string]: Joint? }
	local out: { [string]: Joint? } = {}
	for key, name in JOINT_NAMES do
		local found: Joint? = nil
		for _, d in character:GetDescendants() do
			if d.Name == (name :: string) and (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) then
				found = d :: Joint
				break
			end
		end
		out[key] = found
	end
	return out
end

local function rigFor(character: Model): Rig?
	local rig = rigs[character]
	if rig then
		return rig
	end
	local joints = findJoints(character)
	if not (joints.RShoulder and joints.Waist) then
		return nil
	end
	local created: Rig = { character = character, joints = joints :: any, base = {}, written = {}, clip = nil, weight = 0 }
	rig = created
	rigs[character] = created
	character.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			rigs[character] = nil
		end
	end)
	return created
end

local function euler(v: Vector3): CFrame
	return CFrame.Angles(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
end

-- Starts a move on a character. `speed` > 1 plays faster (cooldowns shorter than the move).
function ArmAnimator.play(character: Model, moveName: string, speed: number)
	local rig = rigFor(character)
	local move = PoseMath.moves()[moveName]
	if not (rig and move) then
		return
	end
	local trails: { Trail } = {}
	if move.trail then
		local all = ArmBuilder.trails(character)
		if move.hand == "R" or move.hand == "B" then
			if all.R then
				table.insert(trails, all.R)
			end
		end
		if move.hand == "L" or move.hand == "B" then
			if all.L then
				table.insert(trails, all.L)
			end
		end
	end
	for _, t in trails do
		t.Enabled = true
	end
	if rig.clip then
		for _, t in rig.clip.trails do
			t.Enabled = false
		end
	end
	rig.clip = { move = move, start = os.clock(), speed = speed, pausedAt = nil, pauseUntil = 0, pausedTotal = 0, trails = trails }
end

-- Freezes a character's current move briefly (impact weight on the attacker).
function ArmAnimator.hitStop(character: Model, seconds: number)
	local rig = rigs[character]
	if rig and rig.clip and seconds > 0 then
		local clip = rig.clip
		if clip.pausedAt == nil then
			clip.pausedAt = os.clock()
			clip.pauseUntil = os.clock() + seconds
		end
	end
end

function ArmAnimator.isPlaying(character: Model): boolean
	local rig = rigs[character]
	return rig ~= nil and rig.clip ~= nil
end

-- 0..1 progress of the current move (nil if idle)
function ArmAnimator.progress(character: Model): number?
	local rig = rigs[character]
	if not (rig and rig.clip) then
		return nil
	end
	local c = rig.clip
	return math.clamp((os.clock() - c.start - c.pausedTotal) * c.speed / c.move.duration, 0, 1)
end

local function restore(rig: Rig)
	for joint, base in rig.base do
		if joint.Parent and rig.written[joint] == joint.Transform then
			setTransform(joint, base)
		end
	end
	table.clear(rig.written)
	table.clear(rig.base)
end

local function apply(rig: Rig, joint: Joint?, offset: CFrame, weight: number)
	if not joint then
		return
	end
	local current = joint.Transform
	local base = if rig.written[joint] == current then (rig.base[joint] or current) else current
	local result = base * (CFrame.identity:Lerp(offset, weight))
	setTransform(joint, result)
	rig.written[joint] = result
	rig.base[joint] = base
end

-- STUDIO-ONLY tooling: holds the local character at one instant of a move (workspace attributes AF_PoseMove and
-- AF_PoseT in 0..1) so key poses can be screenshotted exactly. Inert in live servers.
local function debugPose()
	if not RunService:IsStudio() then
		return
	end
	local moveName = workspace:GetAttribute("AF_PoseMove")
	local char = Players.LocalPlayer.Character
	if type(moveName) ~= "string" or not char then
		return
	end
	local rig = rigFor(char)
	local move = PoseMath.moves()[moveName]
	if not (rig and move) then
		return
	end
	local t = (workspace:GetAttribute("AF_PoseT") :: number?) or 0
	local pose = PoseMath.sample(move, t)
	for key, v in pose do
		if key ~= "RootPos" then
			local offset = euler(v)
			if key == "Root" then
				offset = CFrame.new(pose.RootPos or Vector3.zero) * offset
			end
			apply(rig, rig.joints[key], offset, 1)
		end
	end
	if pose.RootPos and not pose.Root then
		apply(rig, rig.joints.Root, CFrame.new(pose.RootPos), 1)
	end
end

local function step()
	debugPose()
	local now = os.clock()
	for character, rig in rigs do
		if not character.Parent then
			rigs[character] = nil
		else
			local clip = rig.clip
			if clip then
				-- hit-stop: time stands still while paused
				if clip.pausedAt then
					if now >= clip.pauseUntil then
						clip.pausedTotal += now - clip.pausedAt
						clip.pausedAt = nil
					end
				end
				local t = ((clip.pausedAt or now) - clip.start - clip.pausedTotal) * clip.speed / clip.move.duration
				if t >= 1 then
					for _, tr in clip.trails do
						tr.Enabled = false
					end
					rig.clip = nil
				else
					local pose = PoseMath.sample(clip.move, t)
					-- fade the layer in over the first 8% and out over the last 12% so it blends with locomotion
					local w = math.min(1, t / 0.08, (1 - t) / 0.12)
					w = math.clamp(w, 0, 1)
					for key, v in pose do
						if key == "RootPos" then
							-- handled together with Root rotation below
							continue
						end
						local joint = rig.joints[key]
						local offset = euler(v)
						if key == "Root" then
							local pos = pose.RootPos or Vector3.zero
							offset = CFrame.new(pos) * offset
						end
						apply(rig, joint, offset, w)
					end
					if pose.RootPos and not pose.Root then
						apply(rig, rig.joints.Root, CFrame.new(pose.RootPos), w)
					end
				end
			end
		end
	end
end

local started = false

function ArmAnimator.start()
	if started then
		return
	end
	started = true
	local ok, preAnimation = pcall(function(): any
		return (RunService :: any).PreAnimation
	end)
	if ok and typeof(preAnimation) == "RBXScriptSignal" then
		preAnimation:Connect(function()
			for _, rig in rigs do
				restore(rig)
			end
		end)
	end
	RunService.Stepped:Connect(function()
		local good, err = pcall(function(): any
			return step()
		end)
		if not good then
			warn(`[ARMFORGE] ArmAnimator: {err}`)
		end
	end)
end

-- Plays a move on another player's character by user id.
function ArmAnimator.playForUser(userId: number, moveName: string, speed: number)
	local player = Players:GetPlayerByUserId(userId)
	local character = player and player.Character
	if character then
		ArmAnimator.play(character, moveName, speed)
	end
end

return ArmAnimator
