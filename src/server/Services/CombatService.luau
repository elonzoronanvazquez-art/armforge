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
local Validate = require(Shared.Util.Validate)
local RateLimiter = require(Shared.Logic.RateLimiter)
local Rng = require(Shared.Util.Rng)
local Sessions = require(script.Parent.Sessions)
local Sync = require(script.Parent.Sync)
local RockService = require(script.Parent.RockService)

local CombatService = {}

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
	if not session.data.islands.unlocked[entry.island] then
		return false
	end
	return RockService.inReach(entry, hrp.Position, reach, Game.Combat.reachSlack)
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
)
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
		return
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
			if session.data.islands.unlocked[other.island] then
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

	local entry = if rockId > 0 then RockService.get(rockId) else nil
	if entry and not validTarget(session, hrp, entry, stats.reach) then
		entry = nil
	end

	-- everybody (including the attacker's own confirm) sees the swing
	RockService.fxNear(hrp.Position, "Swing", {
		u = player.UserId,
		move = moveName,
		speed = speed,
		armId = stats.armId,
		rock = if entry then entry.id else 0,
		cd = stats.cooldown,
	}, 90)

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
		local comboIndex = Combat.registerStrike(combat, os.clock(), stats.armId)
		local hit = Combat.resolveHit(stats, target.def, comboIndex, rng, nil)
		applyStrike(session, player, target, stats, hit, move, hrp2, nil)
	end)
end

-- Skills ---------------------------------------------------------------------------------------------------------

local function onSkill(player: Player, skillIdRaw: any, rockIdRaw: any)
	local skillId = Validate.id(skillIdRaw)
	local rockId = Validate.int(rockIdRaw, 0, 1e9) or 0
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
	if skillId == "ChargedSmash" then
		local e = if rockId > 0 then RockService.get(rockId) else nil
		if e and validTarget(session, hrp, e, stats.reach) then
			target = e
		else
			return
		end
	end

	-- the skill occupies the attack timeline so the animation is never cut off
	local contact = move.duration * move.contact
	combat.nextAttackAt = math.max(combat.nextAttackAt, now + move.duration * 0.85)
	Combat.startSkill(session.data, combat, skillId, now)
	local arm = Arms.Defs[stats.armId]
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
		rock = if target then target.id else 0,
	}, 110)
	Sync.mark(player)

	if skillId == "ChargedSmash" and target then
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
			local extra: { skill: string?, minChunks: number? } = { skill = skillId, minChunks = effect.minChunks }
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
			-- bounded: at most maxTargets rocks inside the radius, on islands the player has unlocked
			local count = 0
			RockService.fxNear(hrp2.Position, "Wave", { pos = hrp2.Position, radius = effect.radius, color = SkillConfig.Defs[skillId].color }, 110)
			for _, entry in RockService.near(hrp2.Position, effect.radius) do
				if count >= effect.maxTargets then
					break
				end
				if session.data.islands.unlocked[entry.island] then
					count += 1
					local dmg = Combat.mitigate(stats.power * effect.damageMult, entry.def.resistance, stats.pierce)
					RockService.damage(entry, player, player.UserId, dmg, {
						hitDir = (hrp2.Position - entry.center).Unit,
						skill = skillId,
						power = 1.2,
						armId = stats.armId,
						minChunks = 2,
						trailColor = arm.palette.glow,
					})
				end
			end
			session.data.stats.strikes += count
			Sync.mark(player)
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
