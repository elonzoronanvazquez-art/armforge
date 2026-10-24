--!strict
-- Frostpeak climbing: judges climbs on the tagged ClimbRoute trusses (Logic/Climb) and grants Summit Momentum for a finished one, and keeps
-- the mountain's crown a wall by limiting the walkable slope for characters standing on the mountain (Config/Mountain.SlopeLimit).
-- Positions are the client's own, like every proximity check here; Logic/Climb rejects teleports and impossibly fast climbs.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local Climb = require(Shared.Logic.Climb)
local Momentum = require(Shared.Logic.Momentum)
local Mountain = require(Shared.Config.Mountain)
local IslandConfig = require(Shared.Config.Islands)
local Sessions = require(script.Parent.Sessions)
local Sync = require(script.Parent.Sync)
local ProgressService = require(script.Parent.ProgressService)

local ClimbService = {}

local TICK = 0.2

local progress: { [Player]: { [string]: Climb.Progress } } = {}
local lastDone: { [Player]: { [string]: number } } = {}
local routes: { Climb.Route } = {}
local mountainCenter = Vector3.zero

-- The routes are the tagged trusses; their ends are the vertical line through the part.
function ClimbService.collectRoutes(): { Climb.Route }
	local list: { Climb.Route } = {}
	for _, inst in CollectionService:GetTagged("ClimbRoute") do
		if inst:IsA("BasePart") then
			local up = inst.CFrame.UpVector
			local half = inst.Size.Y / 2
			table.insert(list, {
				id = (inst:GetAttribute("RouteId") :: string?) or inst.Name,
				base = inst.Position - up * half,
				top = inst.Position + up * half,
				minSeconds = (inst:GetAttribute("MinSeconds") :: number?) or 2.6,
			})
		end
	end
	return list
end

local function onMountain(pos: Vector3): boolean
	local dx, dz = pos.X - mountainCenter.X, pos.Z - mountainCenter.Z
	return dx * dx + dz * dz <= Mountain.Footprint * Mountain.Footprint
end

local function complete(player: Player, session: Sessions.Session, route: Climb.Route, now: number)
	local done = lastDone[player]
	if not done then
		done = {}
		lastDone[player] = done
	end
	if now - (done[route.id] or -1e9) < Mountain.Climb.cooldown then
		return
	end
	done[route.id] = now
	if Momentum.grant(session, Mountain.Island, now) then
		ProgressService.notify(player, "Toast", { text = `Summit Momentum! {Momentum.text(Mountain.Island) or ""} for 5 minutes.`, kind = "good" })
		Sync.now(player)
	end
end

function ClimbService.step(player: Player, session: Sessions.Session, now: number)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not (hrp and humanoid and humanoid.Health > 0) then
		progress[player] = nil
		return
	end
	local want = if onMountain(hrp.Position) then Mountain.SlopeLimit else Mountain.DefaultSlope
	if humanoid.MaxSlopeAngle ~= want then
		humanoid.MaxSlopeAngle = want
	end
	local mine = progress[player]
	if not mine then
		mine = {}
		progress[player] = mine
	end
	for _, route in routes do
		local p, event = Climb.step(mine[route.id], route, hrp.Position, now)
		if p then
			mine[route.id] = p
		else
			mine[route.id] = nil
		end
		if event == "complete" then
			complete(player, session, route, now)
		end
	end
end

function ClimbService.start()
	local def = IslandConfig.Defs[Mountain.Island]
	if def and def.guardian then
		mountainCenter = Vector3.new(def.guardian.position.X, 0, def.guardian.position.Z)
	end
	routes = ClimbService.collectRoutes()
	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < TICK then
			return
		end
		accum = 0
		local now = os.clock()
		for player, session in Sessions.all() do
			if session.loaded and not session.leaving then
				ClimbService.step(player, session, now)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		progress[player] = nil
		lastDone[player] = nil
	end)
end

return ClimbService
