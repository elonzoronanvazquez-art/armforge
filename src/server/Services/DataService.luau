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

local deepCopy = Persistence.deepCopy

-- saves currently running or queued (any session): BindToClose must outwait leave-saves that started before shutdown
local inflight = 0

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

local function jobId(): string
	return if game.JobId ~= "" then game.JobId else "studio"
end

function DataService.init()
	local name = Game.Data.storeName
	if RunService:IsStudio() then
		name ..= "_Studio"
	end
	DataService.storeName = name
	local ok, result = pcall(function()
		local ds = DataStoreService:GetDataStore(name, Game.Data.storeScope)
		if RunService:IsStudio() then
			-- probe: a failing read reveals "API access disabled" immediately. Read-only, and never done in live servers.
			ds:GetAsync("__probe")
		end
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
		local d, err = Persistence.load(store, key(player.UserId), jobId(), os.time())
		if d then
			data = d
			break
		end
		lastErr = err
		if err == "corrupt" or err == "newer_schema" then
			break -- retrying cannot help; the stored profile is left exactly as it is
		elseif err == "locked" then
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

-- Frees the session lock for a profile that was loaded but never became a live session (the player left mid-load).
-- Only the lock is cleared; the stored data is not rewritten. Yields.
function DataService.releaseLoaded(userId: number)
	if not store then
		return
	end
	local released, err = Persistence.retry(Game.Data.saveRetries, function(seconds: number)
		task.wait(seconds)
	end, function()
		return Persistence.release(store :: any, key(userId), jobId())
	end)
	if not released then
		warn(`[ARMFORGE] could not release the session lock for {userId}: {err} (it expires after {Game.Data.sessionLockTimeout}s)`)
	end
end

-- Yields. Saves the session's data (with retries). release=true frees the session lock. Returns whether it was saved.
-- Saves are serialised per session: an autosave that overlaps another save is skipped, and a releasing save waits for the
-- in-flight one so a late autosave can never re-take the lock after it was released. A leaving session only ever
-- saves with release, and a session whose lock was taken over by another server (lost_lock) never writes again.
function DataService.save(session: Sessions.Session, release: boolean): boolean
	if not store or not session.data or session.flags.lockLost then
		return false
	end
	if session.leaving and not release then
		return false
	end
	if session.flags.saving and not release then
		return false
	end
	inflight += 1
	while session.flags.saving do
		task.wait(0.05)
	end
	if session.flags.lockLost then
		inflight -= 1
		return false
	end
	session.flags.saving = true
	local ok, err = Persistence.retry(Game.Data.saveRetries, function(seconds: number)
		task.wait(seconds)
	end, function()
		return Persistence.save(store :: any, key(session.userId), session.data, jobId(), os.time(), release)
	end)
	session.flags.saving = false
	inflight -= 1
	if ok then
		session.saveFailures = 0
		return true
	end
	session.saveFailures += 1
	warn(`[ARMFORGE] save failed for {session.userId}: {err}`)
	if err == "lost_lock" then
		-- another server owns this profile now: stop writing and remove the player rather than let them play unsaved
		session.flags.lockLost = true
		if not session.leaving and session.player.Parent then
			session.player:Kick("Your save session moved to another server. Please rejoin.")
		end
	end
	return false
end

function DataService.start()
	task.spawn(function()
		while true do
			task.wait(Game.Data.autosaveInterval)
			for _, session in Sessions.all() do
				if session.loaded and not session.leaving and not session.flags.lockLost then
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
		-- ...and outwait leave-saves that were already running when shutdown began
		local deadline = os.clock() + 25
		while (pending > 0 or inflight > 0) and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
