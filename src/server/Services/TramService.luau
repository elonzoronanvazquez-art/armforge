--!strict
-- The Frostpeak aerial tramway. Two cabins hang from one cable and swap ends on a fixed schedule (Logic/Tram). Riders board with the
-- station's prompt while a cabin is docked; the server carries them (anchored, moved with the cabin every frame) and sets them down on
-- the far station's deck. Arriving at the summit grants Summit Momentum. The world builder (Islands/Crystalfall) tags the parts:
--   Tramway model        attributes CableA / CableB (the cabin pivot at each station)
--   TramCabin models     attributes Cabin (1 / 2), Offset (sideways from the cable line)
--   TramStation parts    attributes Station ("base" / "summit"), Exit (where riders are set down); each holds the ProximityPrompt

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local Tram = require(Shared.Logic.Tram)
local Momentum = require(Shared.Logic.Momentum)
local Mountain = require(Shared.Config.Mountain)
local Sessions = require(script.Parent.Sessions)
local Sync = require(script.Parent.Sync)
local ProgressService = require(script.Parent.ProgressService)

local TramService = {}

type Cabin = { model: Model, offset: Vector3 }
type Rider = { cabin: number, slot: number, destination: string }

-- where a rider stands inside a cabin, relative to the cabin pivot (the floor is 6.6 below the cable point)
local SLOTS = { Vector3.new(-1.2, -3.7, -2), Vector3.new(1.2, -3.7, -2), Vector3.new(-1.2, -3.7, 0), Vector3.new(1.2, -3.7, 0), Vector3.new(-1.2, -3.7, 2), Vector3.new(1.2, -3.7, 2) }

local cabins: { [number]: Cabin } = {}
local stations: { [string]: BasePart } = {}
local riders: { [Player]: Rider } = {}
local cableA = Vector3.zero
local cableB = Vector3.zero
local lastText = 0

local function cabinCFrame(cabin: Cabin, f: number): CFrame
	local pos = cableA:Lerp(cableB, f) + cabin.offset
	local dir = cableB - cableA
	return CFrame.lookAt(pos, pos + Vector3.new(dir.X, 0, dir.Z))
end

local function ridersIn(cabin: number): number
	local n = 0
	for _, r in riders do
		if r.cabin == cabin then
			n += 1
		end
	end
	return n
end

local function freeSlot(cabin: number): number
	local used: { [number]: boolean } = {}
	for _, r in riders do
		if r.cabin == cabin then
			used[r.slot] = true
		end
	end
	for i = 1, #SLOTS do
		if not used[i] then
			return i
		end
	end
	return 1
end

local function release(player: Player, rider: Rider)
	riders[player] = nil
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		hrp.Anchored = false
		local station = stations[rider.destination]
		local exit = station and station:GetAttribute("Exit") :: Vector3?
		if exit then
			local spread = Vector3.new(((rider.slot - 1) % 2) * 3 - 1.5, 0, math.floor((rider.slot - 1) / 2) * 3 - 3)
			hrp.CFrame = CFrame.new(exit + spread + Vector3.new(0, 3, 0))
			hrp.AssemblyLinearVelocity = Vector3.zero
		end
	end
end

local function arrived(player: Player, rider: Rider, now: number)
	release(player, rider)
	if rider.destination == "summit" then
		local session = Sessions.ready(player)
		if session and Momentum.grant(session, Mountain.Island, os.clock()) then
			ProgressService.notify(player, "Toast", { text = `Summit Momentum! {Momentum.text(Mountain.Island) or ""} for 5 minutes.`, kind = "good" })
			Sync.now(player)
		end
	end
end

-- A rider pressed a station's prompt.
function TramService.board(player: Player, stationName: string, state: Tram.State): boolean
	local station = stations[stationName]
	local session = Sessions.ready(player)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not (station and session and hrp and humanoid and humanoid.Health > 0) or riders[player] then
		return false
	end
	if (hrp.Position - station.Position).Magnitude > Mountain.Tram.stationRange + 8 then
		return false
	end
	local cabin, why = Tram.canBoard(state, stationName, 0)
	if cabin then
		local count = ridersIn(cabin)
		cabin, why = Tram.canBoard(state, stationName, count)
	end
	if not cabin then
		ProgressService.notify(player, "Toast", { text = why or "The tram cannot take you now.", kind = "warn" })
		return false
	end
	riders[player] = { cabin = cabin, slot = freeSlot(cabin), destination = if stationName == "base" then "summit" else "base" }
	hrp.Anchored = true
	return true
end

local function updateRiders(state: Tram.State, now: number)
	for player, rider in riders do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		if not (hrp and humanoid) or humanoid.Health <= 0 then
			riders[player] = nil
			if hrp then
				hrp.Anchored = false
			end
		elseif state.docked and ((rider.destination == "summit" and state.summitCabin == rider.cabin) or (rider.destination == "base" and state.baseCabin == rider.cabin)) then
			arrived(player, rider, now)
		else
			local cabin = cabins[rider.cabin]
			if cabin then
				hrp.CFrame = cabinCFrame(cabin, Tram.position(state, rider.cabin)) * CFrame.new(SLOTS[rider.slot])
			end
		end
	end
end

local function updatePrompts(state: Tram.State)
	local cfg = Mountain.Tram
	for name, station in stations do
		local prompt = station:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			local up = name == "base"
			local open = state.docked and state.departsIn >= cfg.boardCutoff
			prompt.Enabled = open
			prompt.ActionText = if open then `Ride {if up then "up to the summit" else "down to Base Camp"}  ·  leaves in {math.floor(state.departsIn)}s` else "Tram departing"
			prompt.ObjectText = "Aerial Tramway"
		end
	end
end

function TramService.start()
	local model: Instance? = CollectionService:GetTagged("Tramway")[1]
	if not model then
		return -- no mountain in this world (tests, or a trimmed build)
	end
	cableA = model:GetAttribute("CableA") :: Vector3
	cableB = model:GetAttribute("CableB") :: Vector3
	for _, inst in CollectionService:GetTagged("TramCabin") do
		if inst:IsA("Model") then
			cabins[inst:GetAttribute("Cabin") :: number] = { model = inst, offset = inst:GetAttribute("Offset") :: Vector3 }
		end
	end
	for _, inst in CollectionService:GetTagged("TramStation") do
		if inst:IsA("BasePart") then
			local name = inst:GetAttribute("Station") :: string
			stations[name] = inst
			local prompt = inst:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				prompt.Triggered:Connect(function(player)
					TramService.board(player, name, Tram.state(workspace:GetServerTimeNow()))
				end)
			end
		end
	end
	RunService.Heartbeat:Connect(function()
		local now = workspace:GetServerTimeNow()
		local state = Tram.state(now)
		for index, cabin in cabins do
			cabin.model:PivotTo(cabinCFrame(cabin, Tram.position(state, index)))
		end
		updateRiders(state, now)
		if now - lastText >= 0.5 then
			lastText = now
			updatePrompts(state)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		riders[player] = nil
	end)
end

-- For the dev tools and tests: who is riding which cabin.
function TramService.riderCount(): number
	local n = 0
	for _ in riders do
		n += 1
	end
	return n
end

return TramService
