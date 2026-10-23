--!strict
-- Authoritative rock state machine (pure). The server's RockService owns one State per live rock and routes every
-- hit through apply(); the same code is exercised by tests/rocks.spec.luau.
--
--   INTACT -> SURFACE -> CHIPPED -> FRACTURED -> (collapse) -> RESPAWN
--
-- Damage drives geometry: as health falls, chunks are stripped from the shell, around the point of impact, exposing
-- the mid layer; the final hit collapses everything that is left. Rewards are computed once (state.paid).

local Config = script.Parent.Parent.Config
local RockConfig = require(Config.Rocks)
local Game = require(Config.Game)
local RockGeometry = require(script.Parent.RockGeometry)

local RockSim = {}

export type State = {
	id: number,
	def: RockConfig.RockDef,
	layout: RockGeometry.Layout,
	hp: number,
	maxHp: number,
	alive: boolean,
	stage: string,
	generation: number,
	removed: { [number]: boolean },
	removedCount: number,
	contributors: { [number]: number },
	lastHitter: number?,
	paid: boolean,
	totalDamage: number,
}

export type ApplyResult = {
	ignored: boolean,
	applied: number,
	killed: boolean,
	stage: string,
	prevStage: string,
	stageChanged: boolean,
	hp: number,
	hpFrac: number,
	removed: { number }, -- chunk indices stripped by this hit
	collapse: { number }, -- chunk indices that fell in the final collapse (only when killed)
}

export type Reward = { coins: number, xp: number, shards: number, fraction: number, killer: boolean }

function RockSim.stageFor(frac: number): string
	for _, s in RockConfig.Stages do
		if frac >= s.minFrac - 1e-9 then
			if s.name == "INTACT" and frac < 1 - 1e-9 then
				continue
			end
			return s.name
		end
	end
	return "FRACTURED"
end

function RockSim.new(id: number, def: RockConfig.RockDef, layout: RockGeometry.Layout): State
	return {
		id = id,
		def = def,
		layout = layout,
		hp = def.maxHp,
		maxHp = def.maxHp,
		alive = true,
		stage = "INTACT",
		generation = 1,
		removed = {},
		removedCount = 0,
		contributors = {},
		lastHitter = nil,
		paid = false,
		totalDamage = 0,
	}
end

-- Chunks a hit may strip right now, nearest to the impact direction first.
local function candidates(state: State, hitDir: Vector3?): { number }
	local list: { { index: number, score: number } } = {}
	for _, chunk in state.layout.chunks do
		if chunk.layer <= 2 and not state.removed[chunk.index] then
			local exposed = chunk.layer == 1 or chunk.cover == nil or state.removed[chunk.cover :: number]
			if exposed then
				local score = if hitDir then (1 - chunk.dir:Dot(hitDir)) else chunk.index * 0.001
				-- prefer outer layer on ties so the shell opens before the mineral layer
				score += (chunk.layer - 1) * 0.12
				table.insert(list, { index = chunk.index, score = score })
			end
		end
	end
	table.sort(list, function(a: { index: number, score: number }, b: { index: number, score: number })
		if a.score ~= b.score then
			return a.score < b.score
		end
		return a.index < b.index
	end)
	local out = {}
	for _, entry in list do
		table.insert(out, entry.index)
	end
	return out
end

-- Applies `damage` from `userId`. hitDir is a unit vector from the rock centre toward the point of impact, in the
-- rock's local frame. minChunks forces at least that many chunks to break (skills).
function RockSim.apply(state: State, userId: number, damage: number, hitDir: Vector3?, minChunks: number?): ApplyResult
	local result: ApplyResult = {
		ignored = false,
		applied = 0,
		killed = false,
		stage = state.stage,
		prevStage = state.stage,
		stageChanged = false,
		hp = state.hp,
		hpFrac = state.hp / state.maxHp,
		removed = {},
		collapse = {},
	}
	if not state.alive or damage <= 0 or damage ~= damage then
		result.ignored = true
		return result
	end

	local applied = math.min(state.hp, damage)
	state.hp -= applied
	state.totalDamage += applied
	state.contributors[userId] = (state.contributors[userId] or 0) + applied
	state.lastHitter = userId
	result.applied = applied

	if state.hp <= 1e-9 then
		state.hp = 0
		state.alive = false
		result.killed = true
		for _, chunk in state.layout.chunks do
			if not state.removed[chunk.index] then
				table.insert(result.collapse, chunk.index)
			end
		end
		state.stage = "COLLAPSE"
		result.hp = 0
		result.hpFrac = 0
		result.stage = "COLLAPSE"
		result.stageChanged = result.prevStage ~= "COLLAPSE"
		return result
	end

	local frac = state.hp / state.maxHp
	local removable = state.layout.removable
	local target = math.ceil((1 - frac) * removable - 1e-9)
	local need = math.max(0, target - state.removedCount)
	if minChunks and minChunks > need then
		need = minChunks
	end
	-- never strip the last few removable chunks before the collapse: leave at least 1
	need = math.min(need, math.max(0, removable - state.removedCount - 1))
	if need > 0 then
		local list = candidates(state, hitDir)
		for i = 1, math.min(need, #list) do
			local idx = list[i]
			state.removed[idx] = true
			state.removedCount += 1
			table.insert(result.removed, idx)
		end
	end

	state.stage = RockSim.stageFor(frac)
	result.stage = state.stage
	result.stageChanged = state.stage ~= result.prevStage
	result.hp = state.hp
	result.hpFrac = frac
	return result
end

-- Computes the one-time payout. Returns nil if the rock is not dead or has already paid out.
function RockSim.payout(state: State, rng: { next: (any) -> number }): { [number]: Reward }?
	if state.alive or state.paid then
		return nil
	end
	state.paid = true
	local def = state.def
	local rewards: { [number]: Reward } = {}
	local shardRoll = 0
	if def.shards then
		local lo, hi = def.shards[1], def.shards[2]
		shardRoll = lo + math.floor(rng:next() * (hi - lo + 1))
	end
	local total = state.totalDamage
	if total <= 0 then
		return rewards
	end
	for userId, dmg in state.contributors do
		local share = dmg / total
		local fraction = math.min(1, share / Game.Combat.fullPayoutShare)
		local killer = state.lastHitter == userId
		local bonus = if killer then 1 + Game.Combat.lastHitBonus else 1
		rewards[userId] = {
			coins = math.floor(def.coins * fraction * bonus),
			xp = math.floor(def.xp * fraction * bonus),
			shards = if fraction >= 1 then shardRoll else math.floor(shardRoll * fraction),
			fraction = fraction,
			killer = killer,
		}
	end
	return rewards
end

-- Resets a destroyed rock for its next life. Bumps `generation` so stale delayed hits are discarded.
function RockSim.respawn(state: State)
	state.hp = state.maxHp
	state.alive = true
	state.stage = "INTACT"
	state.removed = {}
	state.removedCount = 0
	state.contributors = {}
	state.lastHitter = nil
	state.paid = false
	state.totalDamage = 0
	state.generation += 1
end

return RockSim
