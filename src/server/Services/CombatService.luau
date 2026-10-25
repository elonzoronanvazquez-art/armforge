--!strict
-- Server-authoritative strikes and skills. The client asks to punch (optionally naming a rock); the server validates the
-- cooldown, equipment, island access and reach, announces the swing to nearby players, and applies the damage at the
-- animation's CONTACT moment (shared/Logic/PoseMath.contactDelay) so the visible hit and the mechanical hit coincide.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local Net = require(Shared.Net)
local Game = require(Shared.Config.Game)
local Arms = require(Shared.Config.Arms)
local SkillConfig = require(Shared.Config.Skills)
local Animations = require(Shared.Config.Animations)
local Combat = require(Shared.Logic.Combat)
local PoseMath = require(Shared.Logic.PoseMath)
local Progression = require(Shared.Logic.Progression)
local Skills = require(Shared.Logic.Skills)
local Signature = require(Shared.Logic.Signature)
local Islands = require(Shared.Logic.Islands)
local Validate = require(Shared.Util.Validate)
local RateLimiter = require(Shared.Logic.RateLimiter)
local Rng = require(Shared.Util.Rng)
local Sessions = require(script.Parent.Sessions)
local Sync = require(script.Parent.Sync)
local RockService = require(script.Parent.RockService)
local EncounterService = require(script.Parent.EncounterService)

local CombatService = {}

type StrikeExtra = { skill: string?, minChunks: number? }

local remotes: Net.Remotes
local limiter = RateLimiter.new()
local rng = Rng.new(os.time() + 5)

local function liveCharacter(player: Player): (Model?, BasePart?)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if char and hum and hrp and hum.Health > 0 and hrp:IsA("BasePart") then
		return char, hrp
	end
	return nil, nil
end

local function allowed(player: Player, action: string): boolean
	local rule = (Game.RateLimits :: any)[action]
	return limiter:take(`{player.UserId}:{action}`, rule.rate, rule.burst, os.clock())
end

-- Whether the player may attack this rock right now (reach, alive, island unlocked).
local function validTarget(session: Sessions.Session, hrp: BasePart, entry: RockService.Entry, reach: number): boolean
	if not Islands.open(session.data, entry.island) then
		return false
	end
	return RockService.inReach(entry, hrp.Position, reach, Game.Combat.reachSlack)
end

-- Whether the player may strike this creature right now (reach + eligibility; the creature must be fightable).
local function validCreature(session: Sessions.Session, hrp: BasePart, enc: EncounterService.Enc, reach: number, extra: number): boolean
	if not EncounterService.inReach(enc, hrp.Position, reach, extra) then
		return false
	end
	return (EncounterService.eligible(session, enc))
end

local function hitDirection(entry: RockService.Entry, hrp: BasePart): Vector3
	local d = hrp.Position - entry.center
	local flat = Vector3.new(d.X, d.Y * 0.35, d.Z)
	if flat.Magnitude < 0.01 then
		return Vector3.new(0, 1, 0)
	end
	return flat.Unit
end

local function hitPosition(entry: RockService.Entry, hrp: BasePart, dir: Vector3): Vector3
	local radius = entry.state.layout.radius
	local height = hrp.Position.Y + 0.6
	local base = entry.center + dir * (radius * 0.92)
	return Vector3.new(base.X, math.clamp(height, entry.base.Position.Y + 0.8, entry.base.Position.Y + entry.state.layout.height), base.Z)
end

-- Applies the resolved strike to the rock and any trait follow-ups (resonance splash, ignite).
local function applyStrike(
	session: Sessions.Session,
	player: Player,
	entry: RockService.Entry,
	stats: Combat.Stats,
	hit: Combat.Hit,
	move: PoseMath.Move,
	hrp: BasePart,
	extra: { skill: string?, minChunks: number? }?
): boolean
	local arm = Arms.Defs[stats.armId]
	local dir = hitDirection(entry, hrp)
	local result = RockService.damage(entry, player, player.UserId, hit.damage, {
		hitDir = dir,
		hitPos = hitPosition(entry, hrp, dir),
		crit = hit.crit,
		rend = hit.rend,
		finisher = hit.finisher,
		skill = extra and extra.skill,
		minChunks = extra and extra.minChunks,
		extraChunks = hit.extraChunks,
		power = move.power,
		armId = stats.armId,
		trailColor = arm.palette.glow,
	})
	if not result then
		return false
	end
	local data = session.data
	data.stats.strikes += 1
	data.stats.totalDamage += result.applied
	if Progression.markTutorial(data, "punched") then
		Sync.mark(player)
	end

	if hit.splash then
		-- Crystal resonance: bounded to the two nearest other rocks
		local count = 0
		for _, other in RockService.near(entry.center, 10, entry.id) do
			if count >= 2 then
				break
			end
			if Islands.open(session.data, other.island) then
				count += 1
				local dmg = Combat.mitigate(hit.raw * 0.3, other.def.resistance, stats.pierce)
				RockService.damage(other, player, player.UserId, dmg, {
					silent = true,
					hitDir = (hrp.Position - other.center).Unit,
					power = 0.5,
				})
			end
		end
	end
	if hit.ignite and entry.state.alive then
		RockService.ignite(entry, player.UserId, math.max(1, math.floor(hit.damage * 0.12)), 3)
	end
	Sync.mark(player)
	return true
end

-- Applies a resolved strike to a creature. The creature's armor, core and interrupt rules live in Logic/CreatureSim.
local function applyCreatureStrike(
	session: Sessions.Session,
	player: Player,
	enc: EncounterService.Enc,
	stats: Combat.Stats,
	hit: Combat.Hit,
	move: PoseMath.Move,
	extra: { skill: string? }?
): boolean
	-- Meltdown has nothing to ignite on a creature, so it adds its burn damage to the strike instead
	local amount = hit.damage * (if hit.ignite then 1.12 else 1)
	local result = EncounterService.hit(enc, player, amount, {
		skill = extra and extra.skill,
		crit = hit.crit,
		rend = hit.rend,
		finisher = hit.finisher,
		power = move.power,
		armId = stats.armId,
	})
	if not result then
		return false
	end
	local data = session.data
	data.stats.strikes += 1
	data.stats.totalDamage += result.applied
	if Progression.markTutorial(data, "punched") then
		Sync.mark(player)
	end
	Sync.mark(player)
	return true
end

type Area = {
	radius: number,
	maxTargets: number,
	mult: number,
	pierce: number,
	ignite: boolean,
	skill: string,
	power: number,
	skipRock: number?,
	skipEnc: number?,
}

-- Area damage around `center`: creatures first (nearest first), then rocks, at most `maxTargets` in all, only on islands
-- the player has open. Shared by Shatter Wave and the signature bursts. Returns how many targets were struck.
local function areaDamage(
	session: Sessions.Session,
	player: Player,
	hrpPos: Vector3,
	center: Vector3,
	stats: Combat.Stats,
	move: PoseMath.Move,
	o: Area
): number
	local count = 0
	local arm = Arms.Defs[stats.armId]
	for _, enc in EncounterService.near(center, o.radius) do
		if count >= o.maxTargets then
			break
		end
		if enc.id ~= o.skipEnc and EncounterService.eligible(session, enc) then
			count += 1
			local dmg = Combat.mitigate(stats.power * o.mult, enc.def.resistance, o.pierce)
			local hit: Combat.Hit = { damage = dmg, crit = false, finisher = false, rend = false, splash = false, ignite = o.ignite, extraChunks = 0, resist = 0, raw = dmg }
			applyCreatureStrike(session, player, enc, stats, hit, move, { skill = o.skill })
		end
	end
	for _, entry in RockService.near(center, o.radius) do
		if count >= o.maxTargets then
			break
		end
		if entry.id ~= o.skipRock and Islands.open(session.data, entry.island) then
			count += 1
			local dmg = Combat.mitigate(stats.power * o.mult, entry.def.resistance, o.pierce)
			local away = hrpPos - entry.center
			RockService.damage(entry, player, player.UserId, dmg, {
				hitDir = if away.Magnitude > 0.01 then away.Unit else Vector3.yAxis,
				skill = o.skill,
				power = o.power,
				armId = stats.armId,
				minChunks = 2,
				trailColor = arm.palette.glow,
			})
			if o.ignite and entry.state.alive then
				RockService.ignite(entry, player.UserId, math.max(1, math.floor(dmg * 0.12)), 3)
			end
		end
	end
	session.data.stats.strikes += count
	Sync.mark(player)
	return count
end

local function onPunch(player: Player, rockIdRaw: any, _seq: any)
	local rockId = Validate.int(rockIdRaw, 0, 1e9)
	if rockId == nil then
		return
	end
	if not allowed(player, "Punch") then
		return
	end
	local session = Sessions.ready(player)
	local char, hrp = liveCharacter(player)
	if not (session and char and hrp) then
		return
	end
	local now = os.clock()
	local combat = session.combat
	Combat.updateBuffs(combat, now)
	if now < combat.nextAttackAt - Game.Combat.cooldownTolerance then
		return -- too early: the client is spamming or desynced; ignore silently
	end
	local stats = Combat.stats(session.data, combat, now)
	combat.nextAttackAt = math.max(now, combat.nextAttackAt) + stats.cooldown
	-- the swing animation follows the chain, but nothing is recorded until the strike lands (see below)
	local swingIndex = Combat.peekStrike(combat, now, stats.armId)

	local arm = Arms.Defs[stats.armId]
	local moveName = PoseMath.moveForCombo(arm.attackStyle, swingIndex)
	local move = PoseMath.moves()[moveName]
	local speed = PoseMath.playSpeed(move, stats.cooldown)
	local delay = PoseMath.contactDelay(move, stats.cooldown)

	-- a creature released from this rock takes priority over the (destroyed) rock it came from
	local creature = if rockId > 0 then EncounterService.targetFor(rockId) else nil
	if creature and not validCreature(session, hrp, creature, stats.reach, Game.Combat.reachSlack) then
		creature = nil
	end
	local entry = if rockId > 0 and not creature then RockService.get(rockId) else nil
	if entry and not validTarget(session, hrp, entry, stats.reach) then
		entry = nil
	end

	-- everybody (including the attacker's own confirm) sees the swing
	RockService.fxNear(hrp.Position, "Swing", {
		u = player.UserId,
		move = moveName,
		speed = speed,
		armId = stats.armId,
		rock = if entry then entry.id elseif creature then creature.id else 0,
		cd = stats.cooldown,
	}, 90)

	if creature then
		local enc: EncounterService.Enc = creature
		local token = enc.sm.token
		task.delay(delay, function()
			if not Sessions.ready(player) then
				return
			end
			local _, hrp2 = liveCharacter(player)
			if not hrp2 or enc.sm.token ~= token or enc.sm.state ~= "COMBAT" then
				return
			end
			if session.data.arms.equipped ~= stats.armId then
				return
			end
			if not validCreature(session, hrp2, enc, stats.reach, Game.Combat.reachSlack + 4) then
				return
			end
			-- the chain is extended only if the strike actually landed (a sealed or invulnerable target refuses it)
			local comboIndex = Combat.peekStrike(combat, os.clock(), stats.armId)
			local hit = Combat.resolveHit(stats, { family = enc.def.family, resistance = enc.def.resistance }, comboIndex, rng, nil)
			if applyCreatureStrike(session, player, enc, stats, hit, move, nil) then
				Combat.registerStrike(combat, os.clock(), stats.armId)
			end
		end)
		return
	end

	if not entry then
		return
	end
	local target: RockService.Entry = entry
	local generation = target.state.generation
	task.delay(delay, function()
		if not Sessions.ready(player) then
			return
		end
		local _, hrp2 = liveCharacter(player)
		if not hrp2 or not target.state.alive or target.state.generation ~= generation then
			return
		end
		-- the attacker may have moved: allow generous slack but not teleporting
		if not RockService.inReach(target, hrp2.Position, stats.reach, Game.Combat.reachSlack + 4) then
			return
		end
		if session.data.arms.equipped ~= stats.armId then
			return -- the arm was swapped mid-swing: the swing belongs to the old arm and lands nothing
		end
		-- a strike that lands (valid target, still alive, in reach) is the only thing that extends combo / Overclock
		-- the chain is extended only if the strike actually landed (a sealed target refuses it)
		local comboIndex = Combat.peekStrike(combat, os.clock(), stats.armId)
		local hit = Combat.resolveHit(stats, target.def, comboIndex, rng, nil)
		if applyStrike(session, player, target, stats, hit, move, hrp2, nil) then
			Combat.registerStrike(combat, os.clock(), stats.armId)
		end
	end)
end

-- Signature moves ---------------------------------------------------------------------------------------------------------

local function onSignature(player: Player, rockIdRaw: any)
	local rockId = Validate.int(rockIdRaw, 0, 1e9) or 0
	if not allowed(player, "Skill") then
		return
	end
	local session = Sessions.ready(player)
	local char, hrp = liveCharacter(player)
	if not (session and char and hrp) then
		return
	end
	local now = os.clock()
	local combat = session.combat
	Combat.updateBuffs(combat, now)
	local stats = Combat.stats(session.data, combat, now)
	local armId = stats.armId
	local def = Signature.def(armId)
	if not def or Signature.remaining(combat, armId, now) > 0 then
		return
	end
	local move = PoseMath.moves()[def.move]

	-- the target: a creature released from the rock first, otherwise the rock itself; both need to be in reach
	local creature: EncounterService.Enc? = nil
	local entry: RockService.Entry? = nil
	local c = if rockId > 0 then EncounterService.targetFor(rockId) else nil
	if c and validCreature(session, hrp, c, stats.reach, Game.Combat.reachSlack) then
		creature = c
	elseif rockId > 0 and not c then
		local e = RockService.get(rockId)
		if e and validTarget(session, hrp, e, stats.reach) then
			entry = e
		end
	end
	if def.needsTarget and not creature and not entry then
		return -- nothing is spent when there is nothing to hit
	end

	combat.nextAttackAt = math.max(combat.nextAttackAt, now + move.duration * 0.9)
	combat.skillReady[Signature.key(armId)] = now + Signature.cooldown(session.data, armId)
	local targetPos: Vector3? = nil
	if creature and creature.sim then
		targetPos = creature.sim.pos
	elseif entry then
		targetPos = entry.center
	end
	RockService.fxNear(hrp.Position, "Signature", {
		u = player.UserId,
		arm = armId,
		move = def.move,
		style = def.style,
		rock = if entry then entry.id elseif creature then creature.id else 0,
		tp = targetPos,
	}, 110)
	Sync.mark(player)

	local sstats = table.clone(stats)
	sstats.pierce = math.min(1, stats.pierce + (def.pierce or 0))
	local token = if creature then creature.sm.token else 0
	local generation = if entry then entry.state.generation else 0
	local skill = "Signature"

	-- is the original target still there to be struck, and the arm still worn?
	local function stillThere(hrp2: BasePart): boolean
		if session.data.arms.equipped ~= armId then
			return false
		end
		if creature then
			return creature.sm.token == token and creature.sm.state == "COMBAT" and validCreature(session, hrp2, creature, stats.reach, Game.Combat.reachSlack + 5)
		elseif entry then
			return entry.state.alive and entry.state.generation == generation and RockService.inReach(entry, hrp2.Position, stats.reach, Game.Combat.reachSlack + 5)
		end
		return true
	end

	local lastIndex = #def.strikes
	for _, strike in def.strikes do
		task.delay(strike.at, function()
			if not Sessions.ready(player) then
				return
			end
			local _, hrp2 = liveCharacter(player)
			if not hrp2 or not stillThere(hrp2) then
				return
			end
			local strikeMove = table.clone(move)
			strikeMove.power = if strike.mult >= 1.5 then 1.6 else 0.7
			if creature then
				local hit = Combat.resolveHit(sstats, { family = creature.def.family, resistance = creature.def.resistance }, 1, rng, { skillMult = strike.mult, noTrait = true, guaranteedCrit = strike.crit })
				hit.ignite = def.ignite == true
				applyCreatureStrike(session, player, creature, sstats, hit, strikeMove, { skill = skill })
			elseif entry then
				local hit = Combat.resolveHit(sstats, entry.def, 1, rng, { skillMult = strike.mult, noTrait = true, guaranteedCrit = strike.crit })
				hit.ignite = def.ignite == true
				applyStrike(session, player, entry, sstats, hit, strikeMove, hrp2, { skill = skill, minChunks = if strike.mult >= 1.5 then 2 else 0 })
			end
		end)
	end

	if stats.trait == "Overclock" and lastIndex > 0 then
		-- Piston Storm leaves the arms fully overclocked for the strikes that follow, even if the target fell mid-move
		task.delay(def.strikes[lastIndex].at + 0.02, function()
			if Sessions.ready(player) and session.data.arms.equipped == armId then
				combat.armId = armId
				combat.overclock = 5
				combat.lastStrike = os.clock()
				combat.combo = math.max(combat.combo, 1)
			end
		end)
	end

	local burst = def.burst
	if burst then
		task.delay(burst.at, function()
			if not Sessions.ready(player) or session.data.arms.equipped ~= armId then
				return
			end
			local _, hrp2 = liveCharacter(player)
			if not hrp2 then
				return
			end
			local center = hrp2.Position
			if burst.center == "target" then
				if creature and creature.sim then
					center = creature.sim.pos
				elseif entry then
					center = entry.center
				end
			end
			RockService.fxNear(center, "Burst", { pos = center, radius = burst.radius, arm = armId, style = def.style, u = player.UserId }, 110)
			areaDamage(session, player, hrp2.Position, center, sstats, move, {
				radius = burst.radius,
				maxTargets = burst.maxTargets,
				mult = burst.mult,
				pierce = sstats.pierce,
				ignite = burst.ignite == true,
				skill = skill,
				power = 1.2,
				skipRock = if entry then entry.id else nil,
				skipEnc = if creature then creature.id else nil,
			})
		end)
	end
end

-- Skills ---------------------------------------------------------------------------------------------------------

local function onSkill(player: Player, skillIdRaw: any, rockIdRaw: any)
	local skillId = Validate.id(skillIdRaw)
	local rockId = Validate.int(rockIdRaw, 0, 1e9) or 0
	if skillId == "Signature" then
		onSignature(player, rockIdRaw)
		return
	end
	if not skillId or not SkillConfig.Defs[skillId] then
		return
	end
	if not allowed(player, "Skill") then
		return
	end
	local session = Sessions.ready(player)
	local char, hrp = liveCharacter(player)
	if not (session and char and hrp) then
		return
	end
	local now = os.clock()
	local combat = session.combat
	Combat.updateBuffs(combat, now)
	local check = Combat.canUseSkill(session.data, combat, skillId, now)
	if not check.ok then
		return
	end
	local stats = Combat.stats(session.data, combat, now)
	local moveName = Animations.SkillMoves[skillId]
	local move = PoseMath.moves()[moveName]
	local rank = check.rank :: number
	local effect = Skills.effect(skillId, rank, stats.armId)

	-- Charged Smash needs a target in reach, otherwise nothing is spent
	local target: RockService.Entry? = nil
	local creatureTarget: EncounterService.Enc? = nil
	if skillId == "ChargedSmash" then
		local c = if rockId > 0 then EncounterService.targetFor(rockId) else nil
		if c and validCreature(session, hrp, c, stats.reach, Game.Combat.reachSlack) then
			creatureTarget = c
		else
			local e = if rockId > 0 and not c then RockService.get(rockId) else nil
			if e and validTarget(session, hrp, e, stats.reach) then
				target = e
			else
				return
			end
		end
	end

	-- the skill occupies the attack timeline so the animation is never cut off
	local contact = move.duration * move.contact
	combat.nextAttackAt = math.max(combat.nextAttackAt, now + move.duration * 0.85)
	Combat.startSkill(session.data, combat, skillId, now)
	if skillId == "Overdrive" then
		task.delay(effect.duration + 0.05, Sync.mark, player)
		task.delay(effect.duration + effect.overheatDuration + 0.05, Sync.mark, player)
	elseif skillId == "CriticalFocus" then
		task.delay(effect.duration + 0.05, Sync.mark, player)
	end

	RockService.fxNear(hrp.Position, "Skill", {
		u = player.UserId,
		skill = skillId,
		move = moveName,
		armId = stats.armId,
		color = SkillConfig.Defs[skillId].color,
		dur = effect.duration,
		tp = if target then target.center elseif creatureTarget and creatureTarget.sim then creatureTarget.sim.pos else nil,
		rock = if target then target.id elseif creatureTarget then creatureTarget.id else 0,
	}, 110)
	Sync.mark(player)

	local chargedExtra: StrikeExtra = { skill = skillId }
	if skillId == "ChargedSmash" and creatureTarget then
		local enc = creatureTarget
		local token = enc.sm.token
		task.delay(contact, function()
			if not Sessions.ready(player) then
				return
			end
			local _, hrp2 = liveCharacter(player)
			if not hrp2 or enc.sm.token ~= token or enc.sm.state ~= "COMBAT" then
				return
			end
			if not validCreature(session, hrp2, enc, stats.reach, Game.Combat.reachSlack + 5) then
				return
			end
			local hit = Combat.resolveHit(stats, { family = enc.def.family, resistance = enc.def.resistance }, 1, rng, { skillMult = effect.damageMult, noTrait = true })
			applyCreatureStrike(session, player, enc, stats, hit, move, chargedExtra)
		end)
	elseif skillId == "ChargedSmash" and target then
		local entry = target
		local generation = entry.state.generation
		task.delay(contact, function()
			if not Sessions.ready(player) then
				return
			end
			local _, hrp2 = liveCharacter(player)
			if not hrp2 or not entry.state.alive or entry.state.generation ~= generation then
				return
			end
			if not RockService.inReach(entry, hrp2.Position, stats.reach, Game.Combat.reachSlack + 5) then
				return
			end
			local hit = Combat.resolveHit(stats, entry.def, 1, rng, { skillMult = effect.damageMult, noTrait = true })
			local extra: StrikeExtra = { skill = skillId, minChunks = effect.minChunks }
			applyStrike(session, player, entry, stats, hit, move, hrp2, extra)
		end)
	elseif skillId == "ShatterWave" then
		task.delay(contact, function()
			if not Sessions.ready(player) then
				return
			end
			local _, hrp2 = liveCharacter(player)
			if not hrp2 then
				return
			end
			-- bounded: at most maxTargets targets (creatures first) inside the radius, on islands the player has unlocked
			RockService.fxNear(hrp2.Position, "Wave", { pos = hrp2.Position, radius = effect.radius, color = SkillConfig.Defs[skillId].color, armId = stats.armId }, 110)
			areaDamage(session, player, hrp2.Position, hrp2.Position, stats, move, {
				radius = effect.radius,
				maxTargets = effect.maxTargets,
				mult = effect.damageMult,
				pierce = stats.pierce,
				ignite = false,
				skill = skillId,
				power = 1.2,
			})
		end)
	end
end

function CombatService.start()
	remotes = Net.server()
	remotes.Punch.OnServerEvent:Connect(onPunch)
	remotes.Skill.OnServerEvent:Connect(onSkill)
	Players.PlayerRemoving:Connect(function(player)
		limiter:clear(`{player.UserId}:`)
	end)
end

return CombatService
