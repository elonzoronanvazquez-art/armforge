--!strict
-- Picks the rock the player's next strike will hit (nearest in reach, preferring the one they face), outlines it, and
-- exposes it to the HUD. The SERVER re-validates every strike; this is only the client's aim assist.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local Signal = require(Shared.Util.Signal)
local Rocks = require(Shared.Config.Rocks)
local Store = require(script.Parent.Parent.Store)

local TargetController = {}

TargetController.changed = Signal.new() :: Signal.Signal<Model?>
TargetController.current = nil :: Model?

local highlight: Highlight
local TAG = "ArmRock"

local function localHrp(): BasePart?
	local char = Players.LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	return if hrp and hrp:IsA("BasePart") then hrp else nil
end

function TargetController.rockCenter(model: Model): Vector3?
	local root = model.PrimaryPart
	return if root then root.Position else nil
end

-- The best rock for a strike right now (nil if none in reach).
function TargetController.pick(): Model?
	local hrp = localHrp()
	if not hrp or not Store.data then
		return nil
	end
	local reach: number = Store.live.reach or 8
	local look = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
	if look.Magnitude > 0.01 then
		look = look.Unit
	end
	local best: Model? = nil
	local bestScore = math.huge
	for _, inst in CollectionService:GetTagged(TAG) do
		local model = inst :: Model
		if model:GetAttribute("Alive") == true and model.PrimaryPart then
			local island = model:GetAttribute("Island")
			if island == nil or Store.data.islands.unlocked[island] then
				local center = model.PrimaryPart.Position
				local radius: number = (model:GetAttribute("Radius") :: number?) or 4
				local delta = center - hrp.Position
				local dist = delta.Magnitude - radius
				if dist <= reach + 1.5 then
					local flat = Vector3.new(delta.X, 0, delta.Z)
					local facing = if flat.Magnitude > 0.01 then flat.Unit:Dot(look) else 1
					local score = dist - facing * 2.5
					if score < bestScore then
						best, bestScore = model, score
					end
				end
			end
		end
	end
	return best
end

function TargetController.start()
	highlight = Instance.new("Highlight")
	highlight.Name = "ArmforgeTarget"
	highlight.FillTransparency = 1
	highlight.OutlineColor = Color3.fromRGB(255, 214, 140)
	highlight.OutlineTransparency = 0.1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Enabled = false
	-- A Highlight with no Adornee outlines its PARENT's descendants, so it lives in its own empty folder.
	local holder = Instance.new("Folder")
	holder.Name = "ArmforgeHighlights"
	holder.Parent = workspace
	highlight.Parent = holder

	task.spawn(function()
		while true do
			task.wait(0.08)
			local target = TargetController.pick()
			if target ~= TargetController.current then
				TargetController.current = target
				highlight.Adornee = target
				highlight.Enabled = target ~= nil
				if target then
					local def = Rocks.Defs[target:GetAttribute("DefId") :: string]
					if def then
						highlight.OutlineColor = def.colors.glow:Lerp(Color3.new(1, 1, 1), 0.35)
					end
				end
				TargetController.changed:fire(target)
			end
		end
	end)
end

return TargetController
