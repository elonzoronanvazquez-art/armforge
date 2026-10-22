--!strict
-- Loads and saves PlayerData through shared/Logic/Persistence (session-locked, versioned, reconciled).
-- Studio runs use a SEPARATE DataStore name from live servers so test saves can never touch production data.
-- If the DataStore is unreachable in Studio (API access off / unpublished place) the service falls back to an
-- in-memory store and says so loudly, so gameplay can still be tested; it does NOT do this in live servers.

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local Game = require(Shared.Config.Game)
local Persistence = require(Shared.Logic.Persistence)
local Sessions = require(script.Parent.Sessions)

local DataService = {}

local store: Persistence.Store? = nil
DataService.usingMemoryStore = false
DataService.storeName = ""

local memory: { [string]: any } = {}

local function deepCopy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = deepCopy(x)
	end
	return out
end

-- Same UpdateAsync contract as a DataStore, kept in a table.
local memoryStore: any = {
	UpdateAsync = function(_, key: string, fn: (any) -> any)
		local new = fn(deepCopy(memory[key]))
		if new == nil then
			return nil
		end
		memory[key] = deepCopy(new)
		return deepCopy(new)
	end,
}

local function key(userId: number): string
	return `Player_{userId}`
end

function DataService.init()
	local name = Game.Data.storeName
	if RunService:IsStudio() then
		name ..= "_Studio"
	end
	DataService.storeName = name
	local ok, result = pcall(function()
		local ds = DataStoreService:GetDataStore(name, Game.Data.storeScope)
		-- probe: a failing UpdateAsync on a throwaway key reveals "API access disabled" immediately
		ds:UpdateAsync("__probe", function(old)
			return old or { probe = true }
		end)
		return ds
	end)
	if ok then
		store = result :: any
		print(`[ARMFORGE] DataStore ready ({name}/{Game.Data.storeScope})`)
	elseif RunService:IsStudio() then
		store = memoryStore
		DataService.usingMemoryStore = true
		warn(`[ARMFORGE] DataStore unavailable in Studio ({tostring(result)}). Using IN-MEMORY storage: progress is NOT saved. Enable Studio Access to API Services and publish the place to test real saves.`)
	else
		store = nil
		warn(`[ARMFORGE] DataStore unavailable: {tostring(result)}`)
	end
end

-- Yields. Returns data or nil (the caller kicks the player rather than risk wiping their save).
function DataService.load(player: Player): any?
	if not store then
		return nil
	end
	local data: any = nil
	local lastErr: string? = nil
	for attempt = 1, Game.Data.loadRetries do
		local d, err = Persistence.load(store, key(player.UserId), game.JobId ~= "" and game.JobId or "studio", os.time())
		if d then
			data = d
			break
		end
		lastErr = err
		if err == "locked" then
			-- another server is still releasing the session; give it a few seconds
			task.wait(3)
		else
			task.wait(math.min(2 ^ attempt, 8))
		end
		if not player.Parent then
			return nil
		end
	end
	if not data then
		warn(`[ARMFORGE] could not load data for {player.Name}: {lastErr}`)
	end
	return data
end

-- Yields. Saves the session's data (with retries). release=true frees the session lock.
function DataService.save(session: Sessions.Session, release: boolean): boolean
	if not store or not session.data then
		return false
	end
	local ok, err = Persistence.retry(Game.Data.saveRetries, function(seconds: number)
		task.wait(seconds)
	end, function()
		return Persistence.save(store :: any, key(session.userId), session.data, game.JobId ~= "" and game.JobId or "studio", os.time(), release)
	end)
	if ok then
		session.saveFailures = 0
		session.dirty = session.dirty
	else
		session.saveFailures += 1
		warn(`[ARMFORGE] save failed for {session.userId}: {err}`)
	end
	return ok
end

function DataService.start()
	task.spawn(function()
		while true do
			task.wait(Game.Data.autosaveInterval)
			for _, session in Sessions.all() do
				if session.loaded and not session.leaving then
					task.spawn(DataService.save, session, false)
				end
			end
		end
	end)
	game:BindToClose(function()
		-- Save everyone in parallel; BindToClose gets ~30s.
		local pending = 0
		for _, session in Sessions.all() do
			if session.loaded and not session.leaving then
				session.leaving = true
				pending += 1
				task.spawn(function()
					DataService.save(session, true)
					pending -= 1
				end)
			end
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
