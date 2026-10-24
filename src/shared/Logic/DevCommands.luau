--!strict
-- Developer commands that only touch a player's DATA (coins, XP, level, rebirths, islands, arms, skills, boosters). Pure, so the whole kit is
-- tested without a server. Commands that need the live world (teleport, god mode, power, speed, reset) are in server/Services/DevMode.
--
-- A command line is `name arg arg`. Names are case-insensitive. Every number is validated and clamped; nothing here trusts its input.

local Config = script.Parent.Parent.Config
local Arms = require(Config.Arms)
local Islands = require(Config.Islands)
local Skills = require(Config.Skills)
local Boosters = require(Config.Boosters)
local Progression = require(Config.Progression)
local Formulas = require(script.Parent.Formulas)
local ProgressionLogic = require(script.Parent.Progression)
local BoosterLogic = require(script.Parent.Boosters)

local DevCommands = {}

export type Result = { ok: boolean, msg: string }

local MAX_COINS = 9e15
local LIMIT = 1e15

-- Splits "coins 5000" into ("coins", { "5000" }).
function DevCommands.parse(line: string): (string, { string })
	local words: { string } = {}
	for word in string.gmatch(line, "%S+") do
		table.insert(words, word)
	end
	local name = string.lower(table.remove(words, 1) or "")
	return name, words
end

local function number(word: string?, lo: number, hi: number): number?
	local n = if word then tonumber(word) else nil
	if n == nil or n ~= n or n == math.huge or n == -math.huge or n < lo or n > hi then
		return nil
	end
	return n
end

local function fail(msg: string): Result
	return { ok = false, msg = msg }
end

local function done(msg: string): Result
	return { ok = true, msg = msg }
end

local function compact(n: number): string
	if math.abs(n) >= 1e12 then
		return string.format("%.2fT", n / 1e12)
	elseif math.abs(n) >= 1e9 then
		return string.format("%.2fB", n / 1e9)
	elseif math.abs(n) >= 1e6 then
		return string.format("%.2fM", n / 1e6)
	elseif math.abs(n) >= 1e3 then
		return string.format("%.1fK", n / 1e3)
	end
	return string.format("%d", n)
end

-- Individual commands --------------------------------------------------------------------------------------------------------

local function addCoins(data: any, n: number)
	data.coins = math.clamp(data.coins + n, 0, MAX_COINS)
end

local function setLevel(data: any, target: number)
	if target > data.level then
		local need = Formulas.totalXpForLevel(target) - Formulas.totalXpForLevel(data.level) - data.xp
		if need > 0 then
			ProgressionLogic.addXp(data, need)
		end
	elseif target < data.level then
		data.level = target
		data.xp = 0
	end
end

local function unlockIslands(data: any): number
	local n = 0
	for id, def in Islands.Defs do
		if not def.comingSoon and not data.islands.unlocked[id] then
			data.islands.unlocked[id] = true
			n += 1
		end
	end
	return n
end

local function completeGuardians(data: any): number
	local n = 0
	for id, def in Islands.Defs do
		if def.guardian and not data.guardians.defeated[id] then
			data.guardians.defeated[id] = true
			data.islands.completed[id] = true
			n += 1
		end
	end
	return n
end

local function unlockArms(data: any, upgrade: boolean): number
	local n = 0
	for id, def in Arms.Defs do
		if not data.arms.owned[id] then
			data.arms.owned[id] = true
			n += 1
		end
		if upgrade then
			data.arms.levels[id] = def.maxLevel
		else
			data.arms.levels[id] = data.arms.levels[id] or 0
		end
	end
	return n
end

local function maxSkills(data: any)
	for id, def in Skills.Defs do
		data.skills.ranks[id] = def.maxRank
	end
end

local function giveBoosters(data: any, count: number)
	for id in Boosters.Defs do
		BoosterLogic.give(data, id, count)
	end
end

local COMMANDS: { [string]: (data: any, args: { string }) -> Result } = {
	coins = function(data, args)
		local n = number(args[1], -LIMIT, LIMIT)
		if not n then
			return fail("usage: coins <amount>  (adds; negative removes)")
		end
		addCoins(data, math.floor(n))
		return done(`coins {if n >= 0 then "+" else ""}{compact(n)} -> {compact(data.coins)}`)
	end,
	setcoins = function(data, args)
		local n = number(args[1], 0, MAX_COINS)
		if not n then
			return fail("usage: setcoins <amount>")
		end
		data.coins = math.floor(n)
		return done(`coins = {compact(data.coins)}`)
	end,
	shards = function(data, args)
		local n = number(args[1], -LIMIT, LIMIT)
		if not n then
			return fail("usage: shards <amount>")
		end
		data.shards = math.clamp(data.shards + math.floor(n), 0, MAX_COINS)
		return done(`shards -> {compact(data.shards)}`)
	end,
	xp = function(data, args)
		local n = number(args[1], 0, LIMIT)
		if not n then
			return fail("usage: xp <amount>")
		end
		local before = data.level
		ProgressionLogic.addXp(data, math.floor(n))
		return done(`xp +{compact(n)}: level {before} -> {data.level}`)
	end,
	level = function(data, args)
		local n = number(args[1], 1, Progression.MaxLevel)
		if not n then
			return fail(`usage: level <1-{Progression.MaxLevel}>`)
		end
		setLevel(data, math.floor(n))
		return done(`level = {data.level}`)
	end,
	rebirths = function(data, args)
		local n = number(args[1], 0, Progression.Rebirth.maxRebirths)
		if not n then
			return fail(`usage: rebirths <0-{Progression.Rebirth.maxRebirths}>`)
		end
		data.rebirths = math.floor(n)
		return done(`rebirths = {data.rebirths}`)
	end,
	unlockislands = function(data)
		local n = unlockIslands(data)
		return done(`unlocked {n} island(s); every playable island is open`)
	end,
	completeguardians = function(data)
		local n = completeGuardians(data)
		return done(`marked {n} guardian(s) defeated`)
	end,
	unlockarms = function(data)
		local n = unlockArms(data, false)
		return done(`gave {n} arm(s)`)
	end,
	maxarms = function(data)
		unlockArms(data, true)
		return done("every arm owned and fully upgraded")
	end,
	skills = function(data)
		maxSkills(data)
		return done("every skill at max rank")
	end,
	boosters = function(data, args)
		local n = number(args[1], 1, 50) or 3
		giveBoosters(data, math.floor(n))
		return done(`+{math.floor(n)} of every booster`)
	end,
	unlockall = function(data)
		local islands = unlockIslands(data)
		local arms = unlockArms(data, false)
		return done(`unlocked {islands} island(s) and {arms} arm(s)`)
	end,
	-- Everything needed to test late content at once.
	kit = function(data)
		setLevel(data, Progression.MaxLevel)
		data.coins = math.max(data.coins, 1e9)
		data.shards = math.max(data.shards, 500)
		data.rebirths = math.max(data.rebirths, 6)
		unlockIslands(data)
		unlockArms(data, true)
		maxSkills(data)
		giveBoosters(data, 3)
		return done("test kit: level 40, 1B coins, 500 shards, 6 rebirths, every island, every arm maxed, every skill, boosters")
	end,
}

DevCommands.Names = {}
for name in COMMANDS do
	table.insert(DevCommands.Names, name)
end
table.sort(DevCommands.Names)

function DevCommands.has(name: string): boolean
	return COMMANDS[name] ~= nil
end

-- Runs a data command on `data`. Unknown names fail (the server tries its own commands first).
function DevCommands.apply(data: any, name: string, args: { string }): Result
	local command = COMMANDS[name]
	if not command then
		return fail(`unknown command "{name}"`)
	end
	return command(data, args)
end

return DevCommands
