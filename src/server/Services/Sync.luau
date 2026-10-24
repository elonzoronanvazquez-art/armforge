--!strict
-- Pushes the owning client its state snapshot. Changes are coalesced: any number of mark() calls within a tick
-- produce one Sync per player at most every MIN_INTERVAL seconds (no per-hit remote spam).

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local Net = require(Shared.Net)
local DataSchema = require(Shared.Logic.DataSchema)
local Combat = require(Shared.Logic.Combat)
local Momentum = require(Shared.Logic.Momentum)
local Sessions = require(script.Parent.Sessions)
local DevAccess = require(script.Parent.DevAccess)

local Sync = {}

local MIN_INTERVAL = 0.1
local remotes: Net.Remotes

local function snapshot(session: Sessions.Session): any
	local snap = DataSchema.snapshot(session.data)
	local now = os.clock()
	local cooldowns: { [string]: number } = {}
	for id, readyAt in session.combat.skillReady do
		local left = readyAt - now
		if left > 0 then
			cooldowns[id] = left
		end
	end
	local buffs: { [string]: number } = {}
	local b = session.combat.buffs
	if b.overdrive and b.overdrive.untilT > now then
		buffs.Overdrive = b.overdrive.untilT - now
	end
	if b.focus and b.focus.untilT > now then
		buffs.CriticalFocus = b.focus.untilT - now
	end
	Combat.updateBuffs(session.combat, now)
	local stats = Combat.stats(session.data, session.combat, now)
	snap.live = {
		cooldowns = cooldowns,
		buffs = buffs,
		power = stats.power,
		cooldown = stats.cooldown,
		critChance = stats.critChance,
		reach = stats.reach,
		momentum = if session.momentum and Momentum.remaining(session, now) > 0 then { island = session.momentum.island, remaining = Momentum.remaining(session, now) } else nil,
		dev = DevAccess.allowed(session.player),
		zone = session.zone,
		serverTime = workspace:GetServerTimeNow(),
	}
	return snap
end

function Sync.mark(player: Player)
	local s = Sessions.get(player)
	if s then
		s.dirty = true
	end
end

-- Immediately sends (used after explicit client requests so the UI never lags the response).
function Sync.now(player: Player)
	local s = Sessions.ready(player)
	if not s then
		return
	end
	s.dirty = false
	s.lastSync = os.clock()
	remotes.Sync:FireClient(player, snapshot(s))
end

function Sync.start()
	remotes = Net.server()
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for player, s in Sessions.all() do
			if s.dirty and s.loaded and not s.leaving and now - s.lastSync >= MIN_INTERVAL then
				Sync.now(player)
			end
		end
	end)
end

return Sync
