--!strict
-- Local attack loop. Input marks "attack wanted"; this controller turns that into strikes at the server-approved cadence:
-- picks a target, plays the procedural swing immediately (so the game feels instant), and tells the server. Damage,
-- rewards and cooldown enforcement are the server's; the client only predicts the animation.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local Net = require(Shared.Net)
local Game = require(Shared.Config.Game)
local Arms = require(Shared.Config.Arms)
local SkillConfig = require(Shared.Config.Skills)
local Animations = require(Shared.Config.Animations)
local PoseMath = require(Shared.Logic.PoseMath)
local Signal = require(Shared.Util.Signal)
local Store = require(script.Parent.Parent.Store)
local ArmAnimator = require(script.Parent.ArmAnimator)
local TargetController = require(script.Parent.TargetController)
local EffectsController = require(script.Parent.EffectsController)

local CombatController = {}

CombatController.struck = Signal.new() :: Signal.Signal<string>
CombatController.blocked = false -- UI panels / training set this to stop strikes

local LOCAL = Players.LocalPlayer
local remotes: Net.Remotes

local held = false
local queued = false
local nextAttackAt = 0
local combo = 0
local lastStrike = -1e9
local lastArm = ""
local cdEstimate = 0.55
local seq = 0

local function character(): (Model?, BasePart?, Humanoid?)
	local char = LOCAL.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if char and hrp and hum and hum.Health > 0 and hrp:IsA("BasePart") then
		return char, hrp, hum
	end
	return nil, nil, nil
end

local function faceTarget(hrp: BasePart, target: Model?)
	if not (target and target.PrimaryPart) then
		return
	end
	local center = target.PrimaryPart.Position
	local flat = Vector3.new(center.X, hrp.Position.Y, center.Z)
	if (flat - hrp.Position).Magnitude < 0.1 then
		return
	end
	local goal = CFrame.lookAt(hrp.Position, flat)
	hrp.CFrame = hrp.CFrame:Lerp(goal, 0.7)
end

local function strike()
	local char, hrp = character()
	if not (char and hrp) or not Store.data then
		return
	end
	local now = os.clock()
	local armId = Store.armId()
	local arm = Arms.Defs[armId]
	local target = TargetController.pick()
	local rockId = if target then (target:GetAttribute("RockId") :: number) else 0

	if armId ~= lastArm then
		lastArm = armId
		combo = 0
	end
	if now - lastStrike <= Game.Combat.comboWindow then
		combo += 1
	else
		combo = 1
	end
	lastStrike = now

	local moveName = PoseMath.moveForCombo(arm.attackStyle, combo)
	local move = PoseMath.moves()[moveName]
	local cd = cdEstimate
	local speed = PoseMath.playSpeed(move, cd)
	faceTarget(hrp, target)
	ArmAnimator.play(char, moveName, speed)
	EffectsController.sound("Swing", hrp.Position, 0.8, 1 + (speed - 1) * 0.3)
	seq += 1
	remotes.Punch:FireServer(rockId, seq)
	nextAttackAt = now + cd
	CombatController.struck:fire(moveName)
end

function CombatController.setHeld(value: boolean)
	held = value
	if value then
		queued = true
	end
end

function CombatController.tap()
	queued = true
end

-- Slot 1..4 -> skill
function CombatController.useSkillSlot(slot: number)
	if not Store.data or CombatController.blocked then
		return
	end
	local skillId: string? = nil
	for _, id in SkillConfig.Order do
		if SkillConfig.Defs[id].key == slot then
			skillId = id
		end
	end
	if not skillId then
		return
	end
	CombatController.useSkill(skillId)
end

function CombatController.useSkill(skillId: string)
	local char, hrp = character()
	if not (char and hrp) or not Store.data then
		return
	end
	local rank = Store.data.skills.ranks[skillId] or 0
	if rank < 1 then
		EffectsController.floatText(hrp.Position + Vector3.new(0, 3, 0), "Learn it in Skills (K)", Color3.fromRGB(255, 200, 120), 1)
		return
	end
	if Store.skillCooldown(skillId) > 0.05 then
		return
	end
	local target = TargetController.pick()
	local rockId = if target then (target:GetAttribute("RockId") :: number) else 0
	if skillId == "ChargedSmash" and rockId == 0 then
		EffectsController.floatText(hrp.Position + Vector3.new(0, 3, 0), "Get closer to a rock", Color3.fromRGB(255, 200, 120), 1)
		return
	end
	local moveName = Animations.SkillMoves[skillId]
	local move = PoseMath.moves()[moveName]
	faceTarget(hrp, target)
	ArmAnimator.play(char, moveName, 1)
	nextAttackAt = math.max(nextAttackAt, os.clock() + move.duration * 0.85)
	remotes.Skill:FireServer(skillId, rockId)
end

function CombatController.start()
	remotes = Net.client()

	-- adopt the cooldown the server actually applied to our last strike
	remotes.Fx.OnClientEvent:Connect(function(kind: string, payload: any)
		if kind == "Swing" and payload.u == LOCAL.UserId and type(payload.cd) == "number" then
			cdEstimate = math.max(Game.Combat.minCooldown, payload.cd)
		end
	end)
	Store.changed:connect(function()
		-- between strikes, follow the server's current cooldown (it includes buffs we cannot see)
		local live = Store.live
		if type(live.cooldown) == "number" and os.clock() - lastStrike > 0.6 then
			cdEstimate = live.cooldown
		end
	end)

	RunService.Heartbeat:Connect(function()
		if CombatController.blocked then
			queued = false
			return
		end
		if (held or queued) and os.clock() >= nextAttackAt then
			queued = false
			strike()
		elseif queued and os.clock() - nextAttackAt > 0.25 then
			queued = false
		end
	end)
end

return CombatController
