--!strict
-- Client-side mirror of the server's state snapshot (Sync remote). The UI and controllers read from here and listen to
-- `changed`; nothing on the client writes game state, it only requests changes through Net.Request.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Arms = require(Shared.Config.Arms)
local Formulas = require(Shared.Logic.Formulas)

local Store = {}

Store.data = nil :: any
Store.live = {} :: any
Store.changed = Signal.new() :: Signal.Signal<any>
Store.ready = false
Store.receivedAt = 0

local remotes: Net.Remotes

function Store.init()
	remotes = Net.client()
	remotes.Sync.OnClientEvent:Connect(function(snapshot: any)
		Store.data = snapshot
		Store.live = snapshot.live or {}
		Store.receivedAt = os.clock()
		Store.ready = true
		Store.changed:fire(snapshot)
	end)
end

function Store.waitReady()
	while not Store.ready do
		task.wait(0.05)
	end
end

function Store.armId(): string
	return Store.data and Store.data.arms.equipped or Arms.StarterId
end

function Store.armLevel(armId: string?): number
	local id = armId or Store.armId()
	return Store.data and Store.data.arms.levels[id] or 0
end

function Store.armPower(armId: string?): number
	local id = armId or Store.armId()
	return Formulas.armPower(id, Store.armLevel(id))
end

-- Remaining seconds of a booster, counting down locally between snapshots.
function Store.boosterRemaining(id: string): number
	local remaining = Store.data and Store.data.boosters.active[id]
	if not remaining then
		return 0
	end
	return math.max(0, remaining - (os.clock() - Store.receivedAt))
end

-- Remaining skill cooldown (seconds), counting down locally.
function Store.skillCooldown(id: string): number
	local left = Store.live.cooldowns and Store.live.cooldowns[id]
	if not left then
		return 0
	end
	return math.max(0, left - (os.clock() - Store.receivedAt))
end

function Store.buffRemaining(id: string): number
	local left = Store.live.buffs and Store.live.buffs[id]
	if not left then
		return 0
	end
	return math.max(0, left - (os.clock() - Store.receivedAt))
end

-- Sends a UI action to the server. Returns the result table ({ok, err?, ...}).
function Store.request(action: string, args: { [string]: any }?): any
	local ok, result = pcall(function()
		return remotes.Request:InvokeServer(action, args or {})
	end)
	if not ok then
		return { ok = false, err = "network" }
	end
	return result
end

return Store
