--!strict
-- Authoritative creature combat state machine (pure). EncounterService owns one Sim per emerged creature, steps it a few
-- times per second with the positions of the players near it, and applies the resulting events (damage to players, effects).
-- Players' hits come in through applyDamage. Nothing here touches Roblox instances, so the whole fight is unit tested.
--
--   EMERGING -> IDLE -> ENGAGED -> WINDUP -> ATTACKING -> RECOVERING -> ENGAGED ...
--                          |                    ^ (interrupted skill)
--                          +--> STAGGERED --> ENGAGED          TRANSITION (boss phase change)         DEFEATED (final)
--
-- Fairness rules: every attack has a visible windup, its area is LOCKED when the windup starts (moving out of it works), it
-- is followed by a recovery in which the creature is committed, and only listed skills can interrupt it. Armor and the
-- exposed core turn learned skills into real tools instead of a bigger health bar.

local Config = script.Parent.Parent.Config
local Creatures = require(Config.Creatures)

local CreatureSim = {}

export type Def = Creatures.CreatureDef
export type Attack = Creatures.Attack

export type Sim = {
	id: number,
	def: Def,
	hp: number,
	maxHp: number,
	alive: boolean,
	state: string,
	enteredAt: number,
	endsAt: number,
	pos: Vector3,
	home: Vector3,
	facing: Vector3,
	target: number?,
	attack: Attack?,
	aimOrigin: Vector3,
	aimDir: Vector3,
	phase: number,
	nextAttackAt: number,
	ready: { [string]: number },
	armorOpenUntil: number,
	coreOpenUntil: number,
	invulnerableUntil: number,
	contributors: { [number]: number },
	totalDamage: number,
	lastHitter: number?,
	paid: boolean,
	idleSince: number,
	noTargetSince: number?,
	damageTaken: number,
}

export type Player = { userId: number, pos: Vector3, alive: boolean, canFight: boolean }

export type Event = { [string]: any }

export type Reward = { coins: number, xp: number, shards: number, fraction: number, killer: boolean }

export type HitOpts = { skill: string?, crit: boolean? }

export type DamageResult = {
	ignored: boolean,
	applied: number,
	killed: boolean,
	armored: boolean, -- the strike met armor
	armorBroken: boolean, -- this strike opened it
	coreHit: boolean,
	interrupted: boolean,
	phaseChanged: boolean,
	hp: number,
	hpFrac: number,
}

local STRIKE_TIME = 0.18 -- how long the ATTACKING pose is shown after the strike lands
local PLAYER_SLACK = 1 -- studs added to every area so a player's body, not just their centre, counts
local PHASE_PAUSE = 1.8

-- (a typed helper: the new solver cannot infer a table literal pushed straight into a list of loose events)
local function push(events: { Event }, e: Event)
	table.insert(events, e)
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function flatDist(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function direction(from: Vector3, to: Vector3, fallback: Vector3): Vector3
	local d = flat(to - from)
	if d.Magnitude < 1e-3 then
		return fallback
	end
	return d.Unit
end

function CreatureSim.new(id: number, def: Def, maxHp: number, pos: Vector3, now: number): Sim
	return {
		id = id,
		def = def,
		hp = maxHp,
		maxHp = maxHp,
		alive = true,
		state = "EMERGING",
		enteredAt = now,
		endsAt = now + def.emerge,
		pos = pos,
		home = pos,
		facing = Vector3.new(0, 0, 1),
		target = nil,
		attack = nil,
		aimOrigin = pos,
		aimDir = Vector3.new(0, 0, 1),
		phase = 1,
		nextAttackAt = now + def.emerge + 0.6,
		ready = {},
		armorOpenUntil = 0,
		coreOpenUntil = 0,
		invulnerableUntil = now + def.emerge,
		contributors = {},
		totalDamage = 0,
		lastHitter = nil,
		paid = false,
		idleSince = now,
		noTargetSince = nil,
		damageTaken = 0,
	}
end

-- Phase modifiers currently in force (the most recently reached phase table, or neutral).
local function phaseMods(sim: Sim): (number, number, number)
	local p = if sim.phase > 1 and sim.def.phases then sim.def.phases[sim.phase - 1] else nil
	if not p then
		return 1, 1, 1
	end
	return p.speedMult or 1, p.windupMult or 1, p.damageMult or 1
end

local function setState(sim: Sim, state: string, now: number, duration: number, events: { Event })
	sim.state = state
	sim.enteredAt = now
	sim.endsAt = now + duration
	push(events, { kind = "state", state = state, duration = duration, attack = if sim.attack then sim.attack.id else nil })
end

-- Is the point inside the attack's locked area?
function CreatureSim.inArea(attack: Attack, origin: Vector3, dir: Vector3, p: Vector3): boolean
	local v = flat(p - origin)
	local dist = v.Magnitude
	if attack.kind == "circle" then
		return dist <= (attack.radius or 5) + PLAYER_SLACK
	elseif attack.kind == "cone" then
		if dist <= 1.5 then
			return true
		end
		if dist > (attack.length or 8) + PLAYER_SLACK then
			return false
		end
		local cosLimit = math.cos(math.rad(attack.halfAngle or 45))
		return v.Unit:Dot(dir) >= cosLimit
	else -- line
		local along = v:Dot(dir)
		if along < -PLAYER_SLACK or along > (attack.length or 10) + PLAYER_SLACK then
			return false
		end
		local across = (v - dir * along).Magnitude
		return across <= (attack.width or 3) / 2 + PLAYER_SLACK
	end
end

local function available(sim: Sim, attack: Attack, now: number, dist: number): boolean
	if (attack.minPhase or 1) > sim.phase or (attack.maxPhase or 99) < sim.phase then
		return false
	end
	if now < (sim.ready[attack.id] or 0) then
		return false
	end
	-- a ranged creature backs off first instead of firing point-blank
	local preferred = sim.def.preferredRange
	if preferred and dist < preferred * 0.7 then
		return false
	end
	return dist <= attack.range
end

local function chooseAttack(sim: Sim, now: number, dist: number, rng: { next: (any) -> number }): Attack?
	local pool: { Attack } = {}
	local total = 0
	for _, a in sim.def.attacks do
		if available(sim, a, now, dist) then
			table.insert(pool, a)
			total += a.weight or 1
		end
	end
	if #pool == 0 then
		return nil
	end
	local roll = rng:next() * total
	for _, a in pool do
		roll -= a.weight or 1
		if roll <= 0 then
			return a
		end
	end
	return pool[#pool]
end

local function nearestTarget(sim: Sim, players: { Player }, range: number): Player?
	local best: Player? = nil
	local bestDist = range
	for _, p in players do
		if p.alive and p.canFight then
			local d = flatDist(p.pos, sim.pos)
			if d <= bestDist and flatDist(p.pos, sim.home) <= sim.def.leash then
				best, bestDist = p, d
			end
		end
	end
	return best
end

local function findPlayer(players: { Player }, userId: number?): Player?
	if not userId then
		return nil
	end
	for _, p in players do
		if p.userId == userId then
			return p
		end
	end
	return nil
end

local function startAttack(sim: Sim, attack: Attack, target: Player, now: number, events: { Event })
	local _, windupMult = phaseMods(sim)
	local windup = attack.windup * windupMult
	sim.attack = attack
	local dir = direction(sim.pos, target.pos, sim.facing)
	sim.facing = dir
	if attack.aim == "self" then
		sim.aimOrigin = sim.pos
	elseif attack.kind == "circle" then
		sim.aimOrigin = Vector3.new(target.pos.X, sim.pos.Y, target.pos.Z)
	else
		sim.aimOrigin = sim.pos
	end
	sim.aimDir = dir
	sim.ready[attack.id] = now + attack.cooldown + windup
	setState(sim, "WINDUP", now, windup, events)
	push(events, {
		kind = "telegraph",
		attack = attack.id,
		shape = attack.kind,
		origin = sim.aimOrigin,
		dir = dir,
		radius = attack.radius,
		length = attack.length,
		width = attack.width,
		halfAngle = attack.halfAngle,
		duration = windup,
		interruptible = attack.interruptible == true,
		text = attack.text,
	})
end

local function resolveAttack(sim: Sim, now: number, players: { Player }, events: { Event })
	local attack = sim.attack
	if not attack then
		return
	end
	local _, _, damageMult = phaseMods(sim)
	for _, p in players do
		if p.alive and p.canFight and CreatureSim.inArea(attack, sim.aimOrigin, sim.aimDir, p.pos) then
			push(events, { kind = "hit", userId = p.userId, damage = attack.damage * damageMult, attack = attack.id })
		end
	end
	if attack.dash and attack.kind == "line" then
		local goal = sim.aimOrigin + sim.aimDir * (attack.length or 10)
		-- never dash out of the creature's leash
		if flatDist(goal, sim.home) > sim.def.leash then
			goal = sim.home + direction(sim.home, goal, sim.aimDir) * sim.def.leash
		end
		sim.pos = Vector3.new(goal.X, sim.pos.Y, goal.Z)
	end
	push(events, { kind = "strike", attack = attack.id, shape = attack.kind, origin = sim.aimOrigin, dir = sim.aimDir, pos = sim.pos })
	setState(sim, "ATTACKING", now, STRIKE_TIME, events)
end

local function disengage(sim: Sim, now: number, events: { Event })
	sim.target = nil
	sim.attack = nil
	sim.noTargetSince = nil
	sim.idleSince = now
	setState(sim, "IDLE", now, 0, events)
	push(events, { kind = "disengage" })
end

-- Advances the creature to `now`. players are the candidates near it (alive/canFight flags decide who can be targeted or hit).
-- Returns the events the caller must apply: state changes, telegraphs, strikes, per-player hits, disengage, despawn.
function CreatureSim.step(sim: Sim, now: number, dt: number, players: { Player }, rng: { next: (any) -> number }): { Event }
	local events: { Event } = {}
	if not sim.alive then
		return events
	end
	local state = sim.state

	if state == "EMERGING" then
		if now >= sim.endsAt then
			sim.idleSince = now
			setState(sim, "IDLE", now, 0, events)
		end
		return events
	elseif state == "STAGGERED" or state == "TRANSITION" then
		if now >= sim.endsAt then
			sim.attack = nil
			sim.nextAttackAt = now + 0.5
			setState(sim, "ENGAGED", now, 0, events)
		end
		return events
	elseif state == "WINDUP" then
		if now >= sim.endsAt then
			resolveAttack(sim, now, players, events)
		end
		return events
	elseif state == "ATTACKING" then
		if now >= sim.endsAt then
			local attack = sim.attack
			if attack then
				if attack.exposesCore and sim.def.core then
					sim.coreOpenUntil = now + attack.recover
					push(events, { kind = "core", open = true, duration = attack.recover })
				end
				setState(sim, "RECOVERING", now, attack.recover, events)
			else
				setState(sim, "ENGAGED", now, 0, events)
			end
		end
		return events
	elseif state == "RECOVERING" then
		if now >= sim.endsAt then
			sim.attack = nil
			sim.nextAttackAt = now + 0.35
			setState(sim, "ENGAGED", now, 0, events)
		end
		return events
	end

	-- IDLE or ENGAGED -------------------------------------------------------------------------------------------
	local target = findPlayer(players, sim.target)
	if target and not (target.alive and target.canFight and flatDist(target.pos, sim.home) <= sim.def.leash) then
		target = nil
	end
	if not target then
		target = nearestTarget(sim, players, if state == "IDLE" then sim.def.aggroRange else sim.def.leash)
	end
	sim.target = if target then target.userId else nil

	if not target then
		if state == "ENGAGED" then
			local since = sim.noTargetSince or now
			sim.noTargetSince = since
			if now - since >= 1.0 then
				disengage(sim, now, events)
			end
		else
			-- idle: recover health and drift home; retreat entirely after a long stretch with nobody around
			if sim.hp < sim.maxHp then
				sim.hp = math.min(sim.maxHp, sim.hp + sim.maxHp * Creatures.Config.healRate * dt)
			end
			if flatDist(sim.pos, sim.home) > 1 then
				local dir = direction(sim.pos, sim.home, sim.facing)
				local step = math.min(sim.def.speed * dt, flatDist(sim.pos, sim.home))
				sim.pos = sim.pos + dir * step
				sim.facing = dir
			end
			if now - sim.idleSince >= Creatures.Config.idleDespawn then
				push(events, { kind = "despawn" })
			end
		end
		return events
	end

	sim.noTargetSince = nil
	if state == "IDLE" then
		setState(sim, "ENGAGED", now, 0, events)
		push(events, { kind = "aggro", userId = target.userId })
	end

	local dist = flatDist(sim.pos, target.pos)
	local speedMult = phaseMods(sim)
	local speed = sim.def.speed * speedMult
	local dir = direction(sim.pos, target.pos, sim.facing)
	sim.facing = dir

	-- ranged creatures keep their distance; everything else closes to melee spacing
	local preferred = sim.def.preferredRange
	local moveDir = 0
	if preferred then
		if dist < preferred * 0.7 then
			moveDir = -1
		elseif dist > preferred then
			moveDir = 1
		end
	elseif dist > sim.def.radius + 1.5 then
		moveDir = 1
	end
	if moveDir ~= 0 then
		local step = speed * dt
		if moveDir > 0 then
			step = math.min(step, math.max(0, dist - (sim.def.radius + 1)))
		end
		local nextPos = sim.pos + dir * (step * moveDir)
		if flatDist(nextPos, sim.home) <= sim.def.leash then
			sim.pos = nextPos
		end
	end

	if now >= sim.nextAttackAt then
		local attack = chooseAttack(sim, now, dist, rng)
		if attack then
			startAttack(sim, attack, target, now, events)
		end
	end
	return events
end

-- Applies a player's strike. amount is the damage the combat maths already produced; the creature's armor / core scale it.
function CreatureSim.applyDamage(sim: Sim, userId: number, amount: number, opts: HitOpts, now: number): DamageResult
	local result: DamageResult = {
		ignored = false,
		applied = 0,
		killed = false,
		armored = false,
		armorBroken = false,
		coreHit = false,
		interrupted = false,
		phaseChanged = false,
		hp = sim.hp,
		hpFrac = sim.hp / sim.maxHp,
	}
	if not sim.alive or sim.state == "DEFEATED" or sim.state == "EMERGING" or now < sim.invulnerableUntil then
		result.ignored = true
		return result
	end
	if amount ~= amount or amount <= 0 then
		result.ignored = true
		return result
	end
	local def = sim.def
	local skill = opts.skill

	-- a breaker skill opens the armor BEFORE the damage is scaled, so the strike that breaks it lands in full
	if def.armor and skill and table.find(def.armor.breakers, skill) then
		if now >= sim.armorOpenUntil then
			result.armorBroken = true
		end
		sim.armorOpenUntil = now + def.armor.breakDuration
	end
	local mult = 1
	if def.core and now < sim.coreOpenUntil then
		mult = def.core.mult
		result.coreHit = true
	elseif def.armor and now >= sim.armorOpenUntil then
		mult = def.armor.mult
		result.armored = true
	end

	local scaled = math.max(1, math.floor(amount * mult + 0.5))
	local applied = math.min(sim.hp, scaled)
	sim.hp -= applied
	sim.totalDamage += applied
	sim.damageTaken += applied
	sim.contributors[userId] = (sim.contributors[userId] or 0) + applied
	sim.lastHitter = userId
	result.applied = applied

	if sim.hp <= 1e-9 then
		sim.hp = 0
		sim.alive = false
		sim.state = "DEFEATED"
		sim.enteredAt = now
		sim.endsAt = now
		sim.attack = nil
		result.killed = true
		result.hp = 0
		result.hpFrac = 0
		return result
	end

	-- an interruptible windup is broken by a listed skill: the attack is cancelled, the creature staggers and its core opens
	if skill and sim.state == "WINDUP" and sim.attack and sim.attack.interruptible and def.interrupters and table.find(def.interrupters, skill) then
		result.interrupted = true
		sim.attack = nil
		sim.state = "STAGGERED"
		sim.enteredAt = now
		sim.endsAt = now + def.staggerTime
		if def.core then
			sim.coreOpenUntil = now + def.staggerTime
		end
	end

	-- boss phases
	local frac = sim.hp / sim.maxHp
	local phases = def.phases
	if phases then
		while phases[sim.phase] and frac <= phases[sim.phase].hpBelow do
			sim.phase += 1
			result.phaseChanged = true
		end
		if result.phaseChanged then
			sim.attack = nil
			sim.state = "TRANSITION"
			sim.enteredAt = now
			sim.endsAt = now + PHASE_PAUSE
			sim.invulnerableUntil = now + PHASE_PAUSE
			sim.coreOpenUntil = 0
		end
	end

	-- being struck while idle wakes it toward the attacker
	if sim.state == "IDLE" then
		sim.target = userId
	end
	result.hp = sim.hp
	result.hpFrac = frac
	return result
end

-- The one-time reward split. base is what a full-share contributor receives. Returns nil unless the creature is dead and
-- has not paid yet; afterwards it can never pay again.
function CreatureSim.payout(sim: Sim, base: { coins: number, xp: number, shards: number }): { [number]: Reward }?
	if sim.alive or sim.paid then
		return nil
	end
	sim.paid = true
	local rewards: { [number]: Reward } = {}
	local total = sim.totalDamage
	if total <= 0 then
		return rewards
	end
	for userId, dmg in sim.contributors do
		local fraction = math.min(1, (dmg / total) / Creatures.Config.fullPayoutShare)
		local killer = sim.lastHitter == userId
		local bonus = if killer then 1 + Creatures.Config.lastHitBonus else 1
		rewards[userId] = {
			coins = math.floor(base.coins * fraction * bonus),
			xp = math.floor(base.xp * fraction * bonus),
			shards = math.floor(base.shards * fraction),
			fraction = fraction,
			killer = killer,
		}
	end
	return rewards
end

-- Armor / core status for the UI and the server (what a strike would do right now).
function CreatureSim.status(sim: Sim, now: number): { armored: boolean, coreOpen: boolean, armorOpen: boolean }
	local def = sim.def
	return {
		armored = def.armor ~= nil and now >= sim.armorOpenUntil and not (def.core ~= nil and now < sim.coreOpenUntil),
		coreOpen = def.core ~= nil and now < sim.coreOpenUntil,
		armorOpen = def.armor ~= nil and now < sim.armorOpenUntil,
	}
end

-- Resets a creature that nobody is fighting: full health, no armor/core state, back home. (Used when an encounter is abandoned.)
function CreatureSim.reset(sim: Sim, now: number)
	sim.hp = sim.maxHp
	sim.pos = sim.home
	sim.target = nil
	sim.attack = nil
	sim.armorOpenUntil = 0
	sim.coreOpenUntil = 0
	sim.contributors = {}
	sim.totalDamage = 0
	sim.lastHitter = nil
	sim.noTargetSince = nil
	sim.idleSince = now
	sim.state = "IDLE"
	sim.enteredAt = now
	sim.endsAt = now
end

return CreatureSim
