--!strict
-- Session-locked persistence core over an injectable DataStore-like `store` (anything with UpdateAsync).
-- The server passes a real DataStore; tests pass a fake. Records look like:
--   { data = <PlayerData>, lock = { jobId = "...", time = <os.time> }, savedAt = <os.time>, schema = <n> }
-- A lock held by another server job blocks loading until it is released or becomes stale (sessionLockTimeout),
-- which protects against the same player being loaded by two servers at once.

local DataSchema = require(script.Parent.DataSchema)
local Game = require(script.Parent.Parent.Config.Game)

local Persistence = {}

export type Store = { UpdateAsync: (Store, string, (any) -> any) -> any }

local function lockedByOther(record: any, jobId: string, now: number): boolean
	local lock = record and record.lock
	return lock ~= nil and lock.jobId ~= jobId and (now - lock.time) < Game.Data.sessionLockTimeout
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = deepCopy(v)
	end
	return out
end

-- Takes the session lock and returns reconciled data. err: "locked" | "error: ..."
function Persistence.load(store: Store, key: string, jobId: string, now: number): (any?, string?, boolean?)
	local blocked = false
	local wasNew = false
	local ok, result = pcall(function()
		return store:UpdateAsync(key, function(old: any)
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
-- Returns ok, err. Fails with "lost_lock" if another job has taken over the session.
function Persistence.save(store: Store, key: string, data: any, jobId: string, now: number, release: boolean): (boolean, string?)
	local lost = false
	data.lastSave = now
	local snapshot = deepCopy(data)
	local ok, err = pcall(function()
		store:UpdateAsync(key, function(old: any)
			if lockedByOther(old, jobId, now) then
				lost = true
				return nil
			end
			local record = old or {}
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
		if err == "lost_lock" or err == "locked" then
			return false, err
		end
		if i < attempts then
			wait(delay)
			delay = math.min(delay * 2, 16)
		end
	end
	return false, lastErr
end

return Persistence
