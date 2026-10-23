--!strict
-- Session-locked persistence core over an injectable DataStore-like `store` (anything with UpdateAsync).
-- The server passes a real DataStore; tests pass a fake. Records look like:
--   { data = <PlayerData>, lock = { jobId = "...", time = <os.time> }, savedAt = <os.time>, schema = <n> }
-- A lock held by another server job blocks loading until it is released or becomes stale (sessionLockTimeout),
-- which protects against the same player being loaded by two servers at once.
-- Saves are FENCED: a save only commits while the record still carries this job's lock. A server whose lock went stale
-- and was taken over (or released by the new owner) therefore gets "lost_lock" instead of overwriting newer progress.
-- Loads refuse records they cannot safely round-trip: "corrupt" (data is not a table) and "newer_schema" (written by a
-- newer server version, which a reconcile + save would silently downgrade).

local DataSchema = require(script.Parent.DataSchema)
local Game = require(script.Parent.Parent.Config.Game)

local Persistence = {}

export type Store = { UpdateAsync: (Store, string, (any) -> any) -> any }

local function lockedByOther(record: any, jobId: string, now: number): boolean
	local lock = record and record.lock
	return lock ~= nil and lock.jobId ~= jobId and (now - lock.time) < Game.Data.sessionLockTimeout
end

local function ownsLock(record: any, jobId: string): boolean
	local lock = record and record.lock
	return lock ~= nil and lock.jobId == jobId
end

-- nil when the record can be loaded and written back safely, otherwise the refusal reason.
local function unreadable(record: any): string?
	if record == nil then
		return nil
	end
	if type(record) ~= "table" then
		return "corrupt"
	end
	if record.data ~= nil and type(record.data) ~= "table" then
		return "corrupt"
	end
	local newest = Game.Data.schemaVersion
	if type(record.schema) == "number" and record.schema > newest then
		return "newer_schema"
	end
	if type(record.data) == "table" and type(record.data.version) == "number" and record.data.version > newest then
		return "newer_schema"
	end
	return nil
end

function Persistence.deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = Persistence.deepCopy(v)
	end
	return out
end

-- Takes the session lock and returns reconciled data. err: "locked" | "corrupt" | "newer_schema" | "error: ..."
-- On any err nothing was written, so the stored profile is exactly as it was.
function Persistence.load(store: Store, key: string, jobId: string, now: number): (any?, string?, boolean?)
	local blocked = false
	local refused: string? = nil
	local wasNew = false
	local ok, result = pcall(function()
		return store:UpdateAsync(key, function(old: any)
			refused = unreadable(old)
			if refused then
				return nil
			end
			if lockedByOther(old, jobId, now) then
				blocked = true
				return nil
			end
			local record = old or {}
			wasNew = old == nil or old.data == nil
			record.lock = { jobId = jobId, time = now }
			return record
		end)
	end)
	if not ok then
		return nil, `error: {tostring(result)}`
	end
	if refused then
		return nil, refused
	end
	if blocked then
		return nil, "locked"
	end
	local data = DataSchema.reconcile(if result then result.data else nil)
	if data.firstJoin == 0 then
		data.firstJoin = now
	end
	return data, nil, wasNew
end

-- Writes the data. release = true also frees the session lock (player leaving).
-- Returns ok, err. Fails with "lost_lock" unless this job still holds the record's lock.
function Persistence.save(store: Store, key: string, data: any, jobId: string, now: number, release: boolean): (boolean, string?)
	local lost = false
	data.lastSave = now
	local snapshot = Persistence.deepCopy(data)
	local ok, err = pcall(function()
		store:UpdateAsync(key, function(old: any)
			if not ownsLock(old, jobId) then
				lost = true
				return nil
			end
			local record = old
			record.data = snapshot
			record.savedAt = now
			record.schema = Game.Data.schemaVersion
			record.lock = if release then nil else { jobId = jobId, time = now }
			return record
		end)
	end)
	if not ok then
		return false, `error: {tostring(err)}`
	end
	if lost then
		return false, "lost_lock"
	end
	return true, nil
end

-- Frees this job's lock without touching the saved data (a session that never went live: the player left mid-load).
-- Returns ok, err. A lock someone else holds is left alone and counts as success: there is nothing of ours to release.
function Persistence.release(store: Store, key: string, jobId: string): (boolean, string?)
	local ok, err = pcall(function()
		store:UpdateAsync(key, function(old: any)
			if type(old) ~= "table" or not ownsLock(old, jobId) then
				return nil
			end
			old.lock = nil
			return old
		end)
	end)
	if not ok then
		return false, `error: {tostring(err)}`
	end
	return true, nil
end

-- Retries fn up to `attempts` times with `wait(seconds)` between tries (backoff doubles).
function Persistence.retry(attempts: number, wait: (number) -> (), fn: () -> (boolean, string?)): (boolean, string?)
	local delay = 1
	local lastErr: string? = nil
	for i = 1, attempts do
		local ok, err = fn()
		if ok then
			return true, nil
		end
		lastErr = err
		if err == "lost_lock" or err == "locked" or err == "corrupt" or err == "newer_schema" then
			return false, err -- retrying cannot change the outcome
		end
		if i < attempts then
			wait(delay)
			delay = math.min(delay * 2, 16)
		end
	end
	return false, lastErr
end

return Persistence
