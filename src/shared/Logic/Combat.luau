--!strict
-- Combat maths: derives live stats from player data + session state, tracks combos, and resolves a strike's
-- damage against a rock. The server is the only place that calls resolveHit for real; the client calls stats()
-- to predict cooldowns so its animation never runs ahead of what the server will accept.

local Config = script.Parent.Parent.Config
local Arms = require(Config.Arms)
local Game = require(Config.Game)
local Formulas = require(script.Parent.Formulas)
local Skills = require(script.Parent.Skills)

local Combat = {}

export type Buffs = {
	overdrive: { untilT: number, haste: number, power: number }?,
	overheat: { untilT: number, startT: number, penalty: number, realPenalty: number }?,
	focus: { untilT: number, bonus: number }?,
}

export type State = {
	combo: number, -- strikes in the current unbroken chain
	lastStrike: number,
	overclock: number,
	armId: string,
	buffs: Buffs,
	skillReady: { [string]: number },
	nextAttackAt: number,
}

export type Stats = {
	armId: string,
	power: number,
	cooldown: number,
	haste: number,
	critChance: number,
	critMult: number,
	pierce: number,
	reach: number,
	trait: string,
}

export type Rng = { next: (any) -> number }

export type HitOpts = { skillMult: number?, guaranteedCrit: boolean?, noTrait: boolean? }

export type Hit = {
	damage: number,
	crit: boolean,
	finisher: boolean,
	rend: boolean,
	splash: boolean,
	ignite: boolean,
	extraChunks: number,
	resist: number,
	raw: number, -- damage before rock resistance
}

function Combat.newState(armId: string): State
	return { combo = 0, lastStrike = -1e9, overclock = 0, armId = armId, buffs = {}, skillReady = {}, nextAttackAt = 0 }
end

local function active(buff: { untilT: number }?, now: number): boolean
	return buff ~= nil and now < buff.untilT
end

local OVERCLOCK_STEP = 0.05
local OVERCLOCK_MAX = 5

function Combat.stats(data: any, state: State, now: number): Stats
	local armId: string = data.arms.equipped
	local arm = Arms.Defs[armId]
	local level = data.arms.levels[armId] or 0
	local train = {
		power = data.training.power.level,
		haste = data.training.haste.level,
		precision = data.training.precision.level,
	}
	local buffs = state.buffs

	local powerBonus = Formulas.trainingStatBonus(train, "power")
		+ Formulas.rebirthBonus(data.rebirths, "power")
		+ Formulas.boosterBonus(data.boosters.active, "power")
	if active(buffs.overdrive, now) then
		powerBonus += (buffs.overdrive :: any).power
	end
	local power = Formulas.armPower(armId, level) * (1 + powerBonus)

	local haste = Formulas.trainingStatBonus(train, "haste")
	if arm.trait == "Overclock" and now - state.lastStrike <= Game.Combat.comboWindow then
		haste += OVERCLOCK_STEP * math.min(OVERCLOCK_MAX, state.overclock)
	end
	if active(buffs.overdrive, now) then
		haste += (buffs.overdrive :: any).haste
	end
	if active(buffs.overheat, now) then
		haste -= (buffs.overheat :: any).penalty
	end
	haste = Formulas.clampHaste(haste)

	local crit = arm.critChance
		+ Formulas.trainingStatBonus(train, "precision")
		+ Formulas.boosterBonus(data.boosters.active, "crit")
	if active(buffs.focus, now) then
		crit += (buffs.focus :: any).bonus
	end

	return {
		armId = armId,
		power = power,
		haste = haste,
		cooldown = math.max(Game.Combat.minCooldown, arm.cooldown / (1 + haste)),
		critChance = math.clamp(crit, 0, Game.Combat.maxCritChance),
		critMult = arm.critMult,
		pierce = arm.pierce,
		reach = arm.reach,
		trait = arm.trait,
	}
end

-- Records a strike at `now` and returns its position in the combo chain (1, 2, 3...).
function Combat.registerStrike(state: State, now: number, armId: string): number
	if armId ~= state.armId then
		state.armId = armId
		state.combo = 0
		state.overclock = 0
	end
	if now - state.lastStrike <= Game.Combat.comboWindow then
		state.combo += 1
		state.overclock = math.min(OVERCLOCK_MAX, state.overclock + 1)
	else
		state.combo = 1
		state.overclock = 1
	end
	state.lastStrike = now
	return state.combo
end

-- Resolves one strike against a rock definition.
--   comboIndex: from registerStrike (drives Finisher / Singularity)
--   opts.skillMult: multiplier for skill strikes (Charged Smash), opts.guaranteedCrit
function Combat.resolveHit(
	stats: Stats,
	rock: { family: string, resistance: number },
	comboIndex: number,
	rng: Rng,
	opts: HitOpts?
): Hit
	local o: HitOpts = opts or {}
	local raw = stats.power * (o.skillMult or 1)
	local hit: Hit = {
		damage = 0,
		crit = false,
		finisher = false,
		rend = false,
		splash = false,
		ignite = false,
		extraChunks = 0,
		resist = 0,
		raw = 0,
	}
	local pierce = stats.pierce

	if not o.noTrait then
		if stats.trait == "Finisher" and comboIndex % 3 == 0 then
			raw *= 1.45
			hit.finisher = true
		elseif stats.trait == "QuarryMaster" then
			if rock.family == "stone" then
				raw *= 1.35
			end
			hit.extraChunks = 1
		elseif stats.trait == "Singularity" and comboIndex % 4 == 0 then
			raw *= 3
			pierce = math.min(1, pierce + 0.6)
			hit.rend = true
		end
	end

	local crit = o.guaranteedCrit == true or rng:next() < stats.critChance
	if crit then
		raw *= stats.critMult
		hit.crit = true
		if stats.trait == "Resonance" and not o.noTrait then
			hit.splash = true
		end
	end
	if stats.trait == "Meltdown" and not o.noTrait then
		hit.ignite = true
	end

	local resist = math.clamp(rock.resistance * (1 - pierce), 0, 0.95)
	hit.resist = resist
	hit.raw = raw
	hit.damage = math.max(1, math.floor(raw * (1 - resist) + 0.5))
	return hit
end

-- Applies a rock's resistance to arbitrary raw damage (splash, burn, skill waves).
function Combat.mitigate(raw: number, resistance: number, pierce: number): number
	local resist = math.clamp(resistance * (1 - pierce), 0, 0.95)
	return math.max(1, math.floor(raw * (1 - resist) + 0.5))
end

-- Skill activation -----------------------------------------------------------------------------------------

export type SkillCheck = { ok: boolean, err: string?, rank: number?, cooldown: number? }

function Combat.canUseSkill(data: any, state: State, id: string, now: number): SkillCheck
	local rank = Skills.rank(data, id)
	if rank < 1 then
		return { ok = false, err = "not_learned" }
	end
	if now < (state.skillReady[id] or 0) then
		return { ok = false, err = "cooldown" }
	end
	return { ok = true, rank = rank, cooldown = Skills.cooldown(data, id) }
end

-- Marks a skill as used and applies its buff (if any). Returns the effect numbers.
function Combat.startSkill(data: any, state: State, id: string, now: number): { [string]: number }
	local rank = Skills.rank(data, id)
	local effect = Skills.effect(id, rank, data.arms.equipped)
	state.skillReady[id] = now + Skills.cooldown(data, id)
	if id == "Overdrive" then
		state.buffs.overdrive = { untilT = now + effect.duration, haste = effect.hasteBonus, power = effect.powerBonus }
		-- overheat only bites once overdrive has ended (see updateBuffs)
		state.buffs.overheat = {
			untilT = now + effect.duration + effect.overheatDuration,
			startT = now + effect.duration,
			penalty = 0,
			realPenalty = effect.overheatPenalty,
		}
	elseif id == "CriticalFocus" then
		state.buffs.focus = { untilT = now + effect.duration, bonus = effect.critBonus }
	end
	return effect
end

-- The overheat penalty only applies once overdrive has ended; call before stats() each time.
function Combat.updateBuffs(state: State, now: number)
	local oh = state.buffs.overheat
	if oh then
		if now >= oh.untilT then
			state.buffs.overheat = nil
		elseif now >= oh.startT then
			oh.penalty = oh.realPenalty
		else
			oh.penalty = 0
		end
	end
	local od = state.buffs.overdrive
	if od and now >= od.untilT then
		state.buffs.overdrive = nil
	end
	local f = state.buffs.focus
	if f and now >= f.untilT then
		state.buffs.focus = nil
	end
end

return Combat
