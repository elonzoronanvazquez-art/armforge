--!strict
-- Remote definitions shared by server and client. The server creates every remote; the client waits for them.
--   C->S events: Punch, Skill, Training       (high frequency, rate limited and validated server side)
--   C->S function: Request                   (UI actions: equip, buy, upgrade, travel, rebirth...)
--   S->C events: Sync (state snapshots), Fx (world effects), Notify (toasts / popups), TrainingS (mini-game state)
-- Nothing a client sends is trusted: the server validates the type, range and cooldown of every call.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.FolderName = "ArmforgeRemotes"
Net.Events = { "Punch", "Skill", "Training", "Sync", "Fx", "Notify", "TrainingS" }
Net.Functions = { "Request" }

export type Remotes = {
	Punch: RemoteEvent,
	Skill: RemoteEvent,
	Training: RemoteEvent,
	Sync: RemoteEvent,
	Fx: RemoteEvent,
	Notify: RemoteEvent,
	TrainingS: RemoteEvent,
	Request: RemoteFunction,
}

local cached: Remotes? = nil

-- Server: creates the remotes folder (idempotent).
function Net.server(): Remotes
	if cached then
		return cached
	end
	assert(RunService:IsServer(), "Net.server() is server only")
	local folder = ReplicatedStorage:FindFirstChild(Net.FolderName)
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = Net.FolderName
	local out: any = {}
	for _, name in Net.Events do
		local e = Instance.new("RemoteEvent")
		e.Name = name
		e.Parent = folder
		out[name] = e
	end
	for _, name in Net.Functions do
		local f = Instance.new("RemoteFunction")
		f.Name = name
		f.Parent = folder
		out[name] = f
	end
	folder.Parent = ReplicatedStorage
	cached = out
	return out
end

-- Client: waits for every remote.
function Net.client(): Remotes
	if cached then
		return cached
	end
	local folder = ReplicatedStorage:WaitForChild(Net.FolderName)
	local out: any = {}
	for _, name in Net.Events do
		out[name] = folder:WaitForChild(name)
	end
	for _, name in Net.Functions do
		out[name] = folder:WaitForChild(name)
	end
	cached = out
	return out
end

return Net
