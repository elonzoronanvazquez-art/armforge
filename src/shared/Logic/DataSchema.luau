--!strict
-- Versioned player-data schema: defaults, validation/reconciliation of loaded data, and migrations.
-- Loaded data is NEVER trusted: reconcile() clamps numbers, drops unknown ids, and fills missing fields.

local Config = script.Parent.Parent.Config
local Game = require(Config.Game)
local Arms = require(Config.Arms)
local Cosmetics = require(Config.Cosmetics)
local Skills = require(Config.Skills)
local Boosters = require(Config.Boosters)
local Islands = require(Config.Islands)
local Training = require(Config.Training)
local Progression = require(Config.Progression)

local DataSchema = {}

local MAX_COINS = 9e15 -- stays exactly representable as a double

function DataSchema.default(): any
	local trainingStats = {}
	for _, stat in Training.StatOrder do
		trainingStats[stat] = { level = 0, points = 0 }
	end
	local ranks = {}
	for _, id in Skills.Order do
		ranks[id] = 0
	end
	return {
		version = Game.Data.schemaVersion,
		coins = Game.Start.coins,
		shards = Game.Start.shards,
		level = Game.Start.level,
		xp = 0,
		skillPoints = 0,
		rebirths = 0,
		arms = {
			owned = { [Arms.StarterId] = true },
			equipped = Arms.StarterId,
			levels = { [Arms.StarterId] = 0 },
		},
		cosmetics = {
			owned = {},
			equipped = {},
		},
		training = trainingStats,
		skills = { ranks = ranks },
		boosters = { inventory = {}, active = {} },
		islands = { unlocked = { [Islands.Start] = true }, current = Islands.Start },
		tutorial = { step = 1, flags = {} },
		settings = { sfx = 1, music = 0.6, shake = 1, reduceFx = false, damageNumbers = true, uiScale = 1 },
		stats = { rocksDestroyed = 0, totalDamage = 0, strikes = 0, playSeconds = 0, trainingSessions = 0 },
		firstJoin = 0,
		lastSave = 0,
	}
end

local function num(value: any, default: number, lo: number, hi: number): number
	if type(value) ~= "number" or value ~= value then
		return default
	end
	return math.clamp(value, lo, hi)
end

local function int(value: any, default: number, lo: number, hi: number): number
	return math.floor(num(value, default, lo, hi))
end

local function bool(value: any, default: boolean): boolean
	if type(value) == "boolean" then
		return value
	end
	return default
end

-- Migration steps keyed by the version they upgrade FROM. Each returns the data at version + 1.
DataSchema.Migrations = {} :: { [number]: (any) -> any }

local function migrate(raw: any): any
	local version = if type(raw.version) == "number" then raw.version else 1
	while version < Game.Data.schemaVersion do
		local step = DataSchema.Migrations[version]
		if step then
			raw = step(raw)
		end
		version += 1
		raw.version = version
	end
	return raw
end

-- Returns a clean, fully populated table built from untrusted input.
function DataSchema.reconcile(raw: any): any
	local out = DataSchema.default()
	if type(raw) ~= "table" then
		return out
	end
	raw = migrate(raw)

	out.coins = math.floor(num(raw.coins, out.coins, 0, MAX_COINS))
	out.shards = math.floor(num(raw.shards, out.shards, 0, MAX_COINS))
	out.level = int(raw.level, 1, 1, Progression.MaxLevel)
	out.xp = math.floor(num(raw.xp, 0, 0, 1e12))
	out.skillPoints = int(raw.skillPoints, 0, 0, 1000)
	out.rebirths = int(raw.rebirths, 0, 0, Progression.Rebirth.maxRebirths)
	out.firstJoin = num(raw.firstJoin, 0, 0, 1e12)
	out.lastSave = num(raw.lastSave, 0, 0, 1e12)

	-- arms
	local rawArms = if type(raw.arms) == "table" then raw.arms else {}
	out.arms.owned = { [Arms.StarterId] = true }
	out.arms.levels = { [Arms.StarterId] = 0 }
	if type(rawArms.owned) == "table" then
		for id, v in rawArms.owned do
			if Arms.Defs[id] and v == true then
				out.arms.owned[id] = true
			end
		end
	end
	if type(rawArms.levels) == "table" then
		for id, lvl in rawArms.levels do
			local def = Arms.Defs[id]
			if def then
				out.arms.levels[id] = int(lvl, 0, 0, def.maxLevel)
			end
		end
	end
	for id in out.arms.owned do
		if out.arms.levels[id] == nil then
			out.arms.levels[id] = 0
		end
	end
	local equipped = rawArms.equipped
	if type(equipped) == "string" and out.arms.owned[equipped] then
		out.arms.equipped = equipped
	else
		out.arms.equipped = Arms.StarterId
	end

	-- cosmetics
	local rawCos = if type(raw.cosmetics) == "table" then raw.cosmetics else {}
	if type(rawCos.owned) == "table" then
		for key, v in rawCos.owned do
			if type(key) == "string" and v == true then
				local kind, id = string.match(key, "^(%a+):(%w+)$")
				if kind and id and (Cosmetics.Kinds :: any)[kind] and (Cosmetics.Kinds :: any)[kind][id] then
					out.cosmetics.owned[key] = true
				end
			end
		end
	end
	if type(rawCos.equipped) == "table" then
		for armId, sel in rawCos.equipped do
			if Arms.Defs[armId] and type(sel) == "table" then
				local clean = {}
				for _, kind in Cosmetics.KindOrder do
					local id = sel[kind]
					local default = (Cosmetics.Defaults :: any)[kind]
					if type(id) == "string" and (Cosmetics.Kinds :: any)[kind][id] then
						-- must be owned unless free
						local entry = (Cosmetics.Kinds :: any)[kind][id]
						if entry.cost == 0 or out.cosmetics.owned[`{kind}:{id}`] then
							clean[kind] = id
						else
							clean[kind] = default
						end
					else
						clean[kind] = default
					end
				end
				out.cosmetics.equipped[armId] = clean
			end
		end
	end

	-- training
	if type(raw.training) == "table" then
		for _, stat in Training.StatOrder do
			local r = raw.training[stat]
			if type(r) == "table" then
				out.training[stat].level = int(r.level, 0, 0, Training.Stats[stat].maxLevel)
				out.training[stat].points = math.floor(num(r.points, 0, 0, 1e9))
			end
		end
	end

	-- skills
	if type(raw.skills) == "table" and type(raw.skills.ranks) == "table" then
		for _, id in Skills.Order do
			out.skills.ranks[id] = int(raw.skills.ranks[id], 0, 0, Skills.Defs[id].maxRank)
		end
	end

	-- boosters
	if type(raw.boosters) == "table" then
		if type(raw.boosters.inventory) == "table" then
			for id, n in raw.boosters.inventory do
				if Boosters.Defs[id] then
					local count = int(n, 0, 0, 999)
					if count > 0 then
						out.boosters.inventory[id] = count
					end
				end
			end
		end
		if type(raw.boosters.active) == "table" then
			for id, remaining in raw.boosters.active do
				local def = Boosters.Defs[id]
				if def then
					local r = num(remaining, 0, 0, def.maxDuration)
					if r > 0 then
						out.boosters.active[id] = r
					end
				end
			end
		end
	end

	-- islands
	if type(raw.islands) == "table" then
		if type(raw.islands.unlocked) == "table" then
			for id, v in raw.islands.unlocked do
				local def = Islands.Defs[id]
				if def and v == true and not def.comingSoon then
					out.islands.unlocked[id] = true
				end
			end
		end
		if type(raw.islands.current) == "string" and out.islands.unlocked[raw.islands.current] then
			out.islands.current = raw.islands.current
		end
	end
	out.islands.unlocked[Islands.Start] = true

	-- tutorial
	if type(raw.tutorial) == "table" then
		out.tutorial.step = int(raw.tutorial.step, 1, 1, #Progression.Tutorial + 1)
		if type(raw.tutorial.flags) == "table" then
			for flag, v in raw.tutorial.flags do
				if type(flag) == "string" and v == true and #flag < 24 then
					out.tutorial.flags[flag] = true
				end
			end
		end
	end

	-- settings
	if type(raw.settings) == "table" then
		out.settings.sfx = num(raw.settings.sfx, out.settings.sfx, 0, 1)
		out.settings.music = num(raw.settings.music, out.settings.music, 0, 1)
		out.settings.shake = num(raw.settings.shake, out.settings.shake, 0, 1)
		out.settings.uiScale = num(raw.settings.uiScale, out.settings.uiScale, 0.7, 1.4)
		out.settings.reduceFx = bool(raw.settings.reduceFx, out.settings.reduceFx)
		out.settings.damageNumbers = bool(raw.settings.damageNumbers, out.settings.damageNumbers)
	end

	-- stats
	if type(raw.stats) == "table" then
		for k in out.stats do
			out.stats[k] = math.floor(num(raw.stats[k], 0, 0, 1e15))
		end
	end

	out.version = Game.Data.schemaVersion
	return out
end

-- Public subset of the data sent to the owning client (everything the UI needs; nothing sensitive).
function DataSchema.snapshot(data: any): any
	return {
		coins = data.coins,
		shards = data.shards,
		level = data.level,
		xp = data.xp,
		skillPoints = data.skillPoints,
		rebirths = data.rebirths,
		arms = data.arms,
		cosmetics = data.cosmetics,
		training = data.training,
		skills = data.skills,
		boosters = data.boosters,
		islands = data.islands,
		tutorial = data.tutorial,
		settings = data.settings,
		stats = data.stats,
	}
end

return DataSchema
