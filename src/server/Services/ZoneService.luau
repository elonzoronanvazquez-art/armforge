--!strict
-- Zones (Config/Zones): The Atlantic Sea and the Canopy Grove. Entering moves the character to the zone's arrival and marks the session
-- (session.zone) so the HUD can say where you are; sailing home, dying or leaving the server clears it. A zone is an event, not a ladder rung:
-- nothing here touches islands.unlocked or islands.current.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local ZoneConfig = require(Shared.Config.Zones)
local IslandConfig = require(Shared.Config.Islands)
local Sessions = require(script.Parent.Sessions)
local Sync = require(script.Parent.Sync)
local ProgressService = require(script.Parent.ProgressService)
local PlayerService = require(script.Parent.PlayerService)

local ZoneService = {}

local function hrpOf(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Sends the player to a zone. Returns ok, reason.
function ZoneService.enter(player: Player, zoneId: string): (boolean, string?)
	local def = ZoneConfig.Defs[zoneId]
	local session = Sessions.ready(player)
	local hrp = hrpOf(player)
	if not (def and session and hrp) then
		return false, "not_ready"
	end
	if hrp.Anchored then
		return false, "busy" -- riding the tramway
	end
	session.zone = zoneId
	hrp.CFrame = CFrame.new(def.arrival + Vector3.new(0, 3, 0)) * CFrame.Angles(0, math.rad(180), 0)
	hrp.AssemblyLinearVelocity = Vector3.zero
	ProgressService.notify(player, "Island", { id = def.id, name = def.name, tagline = def.tagline })
	Sync.now(player)
	return true, nil
end

-- Brings the player home: the zone's `home` island, or the ladder island they were last on.
function ZoneService.leave(player: Player): (boolean, string?)
	local session = Sessions.ready(player)
	local hrp = hrpOf(player)
	if not (session and hrp) then
		return false, "not_ready"
	end
	local zone = if session.zone then ZoneConfig.Defs[session.zone] else nil
	local island = (zone and zone.home) or session.data.islands.current
	if not IslandConfig.Defs[island] or not session.data.islands.unlocked[island] then
		island = session.data.islands.current
	end
	session.zone = nil
	hrp.CFrame = PlayerService.spawnCFrame(island)
	hrp.AssemblyLinearVelocity = Vector3.zero
	local def = IslandConfig.Defs[island]
	ProgressService.notify(player, "Island", { id = island, name = def.name, tagline = def.tagline })
	Sync.now(player)
	return true, nil
end

-- Is the player's body actually in (or over) the zone they are marked as being in? (Falling off the grove, swimming away from the atoll.)
function ZoneService.inside(zoneId: string, pos: Vector3): boolean
	local def = ZoneConfig.Defs[zoneId]
	if not def then
		return false
	end
	local dx, dz = pos.X - def.center.X, pos.Z - def.center.Z
	local reach = def.radius + (if def.floating then 12 else 70)
	return dx * dx + dz * dz <= reach * reach and math.abs(pos.Y - def.center.Y) <= (if def.floating then 40 else 90)
end

-- Clears the zone mark of anyone who is no longer there.
function ZoneService.start()
	task.spawn(function()
		while true do
			task.wait(2)
			for player, session in Sessions.all() do
				if session.zone then
					local hrp = hrpOf(player)
					if not hrp or not ZoneService.inside(session.zone, hrp.Position) then
						session.zone = nil
						Sync.mark(player)
					end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local s = Sessions.get(player)
		if s then
			s.zone = nil
		end
	end)
end

function ZoneService.current(player: Player): string?
	local s = Sessions.get(player)
	return if s then s.zone else nil
end

return ZoneService
