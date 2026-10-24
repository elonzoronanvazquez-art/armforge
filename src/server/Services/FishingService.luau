--!strict
-- Dock fishing. The world builder tags the end of the dock `FishingSpot` (with a ProximityPrompt); pressing the prompt casts, and pressing it
-- again reels. Logic/Fishing decides the timing and the catch; this service keeps one cast per player, pays the catch (Services/ProgressService),
-- tells the client what is happening (Notify "Fishing") and, one catch in ten, lets the tide pull the angler out to The Atlantic Sea.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local Fishing = require(Shared.Logic.Fishing)
local FishingConfig = require(Shared.Config.Fishing)
local Rng = require(Shared.Util.Rng)
local Sessions = require(script.Parent.Sessions)
local ProgressService = require(script.Parent.ProgressService)
local ZoneService = require(script.Parent.ZoneService)

local FishingService = {}

type State = { cast: Fishing.Cast?, token: number, readyAt: number }

local states: { [Player]: State } = {}
local rng = Rng.new(os.time() + 4242)
local spots: { BasePart } = {}

-- Tests and the dev tools can swap the random source (e.g. to force a sail).
function FishingService.setRng(r: any)
	rng = r
end

local function stateOf(player: Player): State
	local s = states[player]
	if not s then
		s = { cast = nil, token = 0, readyAt = 0 }
		states[player] = s
	end
	return s
end

local function nearSpot(player: Player): boolean
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return false
	end
	for _, spot in spots do
		if (spot.Position - hrp.Position).Magnitude <= FishingConfig.Config.range + 6 then
			return true
		end
	end
	return false
end

local function tell(player: Player, payload: { [string]: any })
	ProgressService.notify(player, "Fishing", payload)
end

-- The prompt was pressed: cast if idle, otherwise reel.
function FishingService.trigger(player: Player, now: number): string
	local session = Sessions.ready(player)
	if not session then
		return "not_ready"
	end
	if not nearSpot(player) then
		return "too_far"
	end
	local state = stateOf(player)
	local cfg = FishingConfig.Config
	if not state.cast then
		if now < state.readyAt then
			return "cooldown"
		end
		local cast = Fishing.cast(now, rng)
		state.cast = cast
		state.token += 1
		local token = state.token
		tell(player, { phase = "cast" })
		-- the bite, then the give-up, are scheduled; a reel, a new cast or leaving invalidates them through the token
		task.delay(cast.biteAt - now, function()
			if states[player] == state and state.token == token and state.cast == cast then
				tell(player, { phase = "bite", window = cfg.reelWindow })
			end
		end)
		task.delay(cast.expiresAt - now + 0.05, function()
			if states[player] == state and state.token == token and state.cast == cast then
				state.cast = nil
				state.readyAt = os.clock() + cfg.cooldown
				tell(player, { phase = "missed" })
			end
		end)
		return "cast"
	end
	local cast = state.cast
	local outcome = Fishing.reel(cast, now)
	state.cast = nil
	state.token += 1
	state.readyAt = now + cfg.cooldown
	if outcome == "early" then
		tell(player, { phase = "early" })
		return "early"
	elseif outcome == "missed" then
		tell(player, { phase = "missed" })
		return "missed"
	end
	local caught = Fishing.roll(rng, session.data.level)
	local coins, xp = ProgressService.eventReward(player, caught.coins, caught.xp, "Forgeheart") -- the dock is on the start island
	tell(player, { phase = "catch", name = caught.fish.name, text = caught.fish.text, coins = coins, xp = xp, sail = caught.sail })
	if caught.sail then
		task.delay(1.4, function()
			if player.Parent and Sessions.ready(player) then
				ZoneService.enter(player, "AtlanticSea")
			end
		end)
		return "sail"
	end
	return "caught"
end

function FishingService.start()
	for _, inst in CollectionService:GetTagged("FishingSpot") do
		if inst:IsA("BasePart") then
			table.insert(spots, inst)
			local prompt = inst:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				prompt.Triggered:Connect(function(player)
					FishingService.trigger(player, os.clock())
				end)
			end
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

-- For tests: is a cast in the water?
function FishingService.casting(player: Player): boolean
	local s = states[player]
	return s ~= nil and s.cast ~= nil
end

return FishingService
