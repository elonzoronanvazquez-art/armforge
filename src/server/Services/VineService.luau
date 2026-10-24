--!strict
-- The jungle's swing vines and the secret above them. Each tagged `SwingVine` part carries a ProximityPrompt; a swing has a 2% chance
-- (Config/Fishing.Vines) to fling the player up to The Canopy Grove. In the grove a gift (`GroveGift`, once per cooldown) and a way down
-- (`GroveExit`) wait. Everything is rolled and paid on the server.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local Fishing = require(Shared.Logic.Fishing)
local FishingConfig = require(Shared.Config.Fishing)
local ZoneConfig = require(Shared.Config.Zones)
local RockConfig = require(Shared.Config.Rocks)
local Rng = require(Shared.Util.Rng)
local Sessions = require(script.Parent.Sessions)
local ProgressService = require(script.Parent.ProgressService)
local ZoneService = require(script.Parent.ZoneService)

local VineService = {}

local rng = Rng.new(os.time() + 777)
local lastSwing: { [Player]: number } = {}
local lastGift: { [Player]: number } = {}

function VineService.setRng(r: any)
	rng = r
end

local function distance(player: Player, part: BasePart): number
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return if hrp then (hrp.Position - part.Position).Magnitude else math.huge
end

-- A short visual sway of the vine's model.
local function sway(part: BasePart)
	local model = part:FindFirstAncestorOfClass("Model")
	if not (model and model.PrimaryPart) then
		return
	end
	local origin = model:GetPivot()
	task.spawn(function()
		local value = Instance.new("NumberValue")
		local conn = value:GetPropertyChangedSignal("Value"):Connect(function()
			model:PivotTo(origin * CFrame.Angles(value.Value, 0, 0))
		end)
		local tween = TweenService:Create(value, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, true), { Value = 0.35 })
		tween:Play()
		tween.Completed:Wait()
		conn:Disconnect()
		model:PivotTo(origin)
		value:Destroy()
	end)
end

-- A swing. Returns "too_far" | "cooldown" | "flung" | "swung" | "not_ready".
function VineService.swing(player: Player, vine: BasePart, now: number): string
	local session = Sessions.ready(player)
	if not session then
		return "not_ready"
	end
	if distance(player, vine) > FishingConfig.Vines.range + 6 then
		return "too_far"
	end
	if now - (lastSwing[player] or -1e9) < FishingConfig.Vines.cooldown then
		return "cooldown"
	end
	lastSwing[player] = now
	pcall(sway, vine) -- purely visual: a failure must never cost the swing
	if Fishing.vineFlings(rng) then
		ProgressService.notify(player, "Toast", { text = "The vine snaps taut and flings you up through the canopy!", kind = "good" })
		task.delay(0.5, function()
			if player.Parent and Sessions.ready(player) then
				ZoneService.enter(player, "CanopyGrove")
			end
		end)
		return "flung"
	end
	ProgressService.notify(player, "Toast", { text = "You swing across the clearing. Nothing happens... this time.", kind = "info" })
	return "swung"
end

-- The grove's gift. Returns "ok" | "cooldown" | "not_in_grove" | "not_ready".
function VineService.gift(player: Player, now: number): string
	local session = Sessions.ready(player)
	if not session then
		return "not_ready"
	end
	local zone = ZoneConfig.Defs.CanopyGrove
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if session.zone ~= "CanopyGrove" or not zone.gift or not (hrp and ZoneService.inside("CanopyGrove", hrp.Position)) then
		return "not_in_grove"
	end
	local left = zone.gift.cooldown - (now - (lastGift[player] or -1e9))
	if left > 0 then
		ProgressService.notify(player, "Toast", { text = `The Rootmother's gift is still growing back ({math.ceil(left)}s).`, kind = "warn" })
		return "cooldown"
	end
	lastGift[player] = now
	local ref = RockConfig.Defs[zone.gift.rock]
	local coins, xp = ProgressService.eventReward(player, ref.coins * zone.gift.mult, ref.xp * zone.gift.mult, "CanopyGrove")
	ProgressService.notify(player, "Toast", { text = `The Rootmother's gift: +{coins} coins, +{xp} XP`, kind = "good" })
	return "ok"
end

function VineService.start()
	for _, inst in CollectionService:GetTagged("SwingVine") do
		if inst:IsA("BasePart") then
			local prompt = inst:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				prompt.Triggered:Connect(function(player)
					VineService.swing(player, inst, os.clock())
				end)
			end
		end
	end
	for _, inst in CollectionService:GetTagged("GroveGift") do
		local prompt = inst:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Triggered:Connect(function(player)
				VineService.gift(player, os.clock())
			end)
		end
	end
	for _, inst in CollectionService:GetTagged("GroveExit") do
		local prompt = inst:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Triggered:Connect(function(player)
				ZoneService.leave(player)
			end)
		end
	end
	for _, inst in CollectionService:GetTagged("ZoneExit") do
		local prompt = inst:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Triggered:Connect(function(player)
				ZoneService.leave(player)
			end)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		lastSwing[player] = nil
		lastGift[player] = nil
	end)
end

return VineService
