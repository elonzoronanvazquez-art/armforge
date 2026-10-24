-- Fight simulation: a scripted player (reacts to telegraphs, closes to melee, punches, uses its skills) against the real
-- CreatureSim, with the real Combat maths for the player's damage. It answers the design questions with numbers:
--   * can a competent player with the RECOMMENDED loadout beat each creature, in a sensible time, without dying?
--   * does a player who ignores the mechanic (no required skill / standing still) do clearly worse on elites and guardians?
-- Time is simulated (50 ms steps); nothing here touches Roblox.
local roblox = require("@lune/roblox")

return function(t, u)
	local Sim = u:load("Logic/CreatureSim")
	local Combat = u:load("Logic/Combat")
	local Schema = u:load("Logic/DataSchema")
	local Creatures = u:load("Config/Creatures")
	local Rocks = u:load("Config/Rocks")
	local Skills = u:load("Config/Skills")
	local SkillLogic = u:load("Logic/Skills")
	local Rng = u:load("Util/Rng")
	local V = roblox.Vector3

	local DT = 0.05
	local RUN = 16 -- studs per second a player can sidestep
	local REACTION = 0.35

	local CreatureStats = u:load("Logic/CreatureStats")
	local function creatureFor(id)
		local def = Creatures.Defs[id]
		return def, CreatureStats.maxHp(def)
	end

	-- A player profile: which arm (owned at `armLevel`), which skills, how many rebirths.
	local function profile(opts)
		local d = Schema.default()
		d.arms.owned[opts.arm] = true
		d.arms.levels[opts.arm] = opts.armLevel or 0
		d.arms.equipped = opts.arm
		d.rebirths = opts.rebirths or 0
		d.level = opts.level or 10
		for id, rank in opts.skills or {} do
			d.skills.ranks[id] = rank
		end
		return d
	end

	-- Returns { won, died, time, hpLeft, punches, skillUses }
	local function fight(creatureId, data, seed, tactics)
		tactics = tactics or {}
		local def, hp = creatureFor(creatureId)
		local rng = Rng.new(seed)
		local combat = Combat.newState(data.arms.equipped)
		local sim = Sim.new(1, def, hp, V.new(0, 0, 0), 0)
		local pos = V.new(0, 0, def.radius + 4)
		local health = 100
		local now = 0
		local nextPunch = 0
		local threats = {}
		local punches, skillUses = 0, 0
		local skillReady = {}
		local stats = Combat.stats(data, combat, 0)
		local result = { won = false, died = false, time = 0, hpLeft = 0, punches = 0, skillUses = 0, hits = {} }

		local function inReach()
			local dx, dz = pos.X - sim.pos.X, pos.Z - sim.pos.Z
			return math.sqrt(dx * dx + dz * dz) <= stats.reach + def.radius - 0.3
		end

		local function dist()
			local dx, dz = pos.X - sim.pos.X, pos.Z - sim.pos.Z
			return math.sqrt(dx * dx + dz * dz)
		end

		local function stepTo(goal, speed)
			local d = goal - pos
			local flat = V.new(d.X, 0, d.Z)
			if flat.Magnitude < 0.05 then
				return
			end
			pos = pos + flat.Unit * math.min(flat.Magnitude, speed * DT)
		end

		local function useSkill(id)
			local rank = data.skills.ranks[id] or 0
			if rank < 1 or now < (skillReady[id] or 0) then
				return false
			end
			if id == "ChargedSmash" then
				if not inReach() then
					return false
				end
				local effect = SkillLogic.effect(id, rank, data.arms.equipped)
				local hit = Combat.resolveHit(stats, { family = def.family, resistance = def.resistance }, 1, rng, { skillMult = effect.damageMult, noTrait = true })
				Sim.applyDamage(sim, 1, hit.damage, { skill = id, crit = hit.crit }, now)
			elseif id == "ShatterWave" then
				local effect = SkillLogic.effect(id, rank, data.arms.equipped)
				if dist() > effect.radius + def.radius then
					return false
				end
				local dmg = Combat.mitigate(stats.power * effect.damageMult, def.resistance, stats.pierce)
				Sim.applyDamage(sim, 1, dmg, { skill = id }, now)
			else
				return false
			end
			skillReady[id] = now + SkillLogic.cooldown(data, id)
			skillUses += 1
			nextPunch = math.max(nextPunch, now + 0.55)
			return true
		end

		local lastLog = 0
		while now < (tactics.maxSeconds or 600) do
			now += DT
			if tactics.trace and now - lastLog >= 20 then
				lastLog = now
				print(string.format("  [trace] t=%.0f hp=%.0f/%.0f state=%s phase=%d bot=(%.0f,%.0f) boss=(%.0f,%.0f) health=%.0f", now, sim.hp, sim.maxHp, sim.state, sim.phase, pos.X, pos.Z, sim.pos.X, sim.pos.Z, health))
			end
			local events = Sim.step(sim, now, DT, { { userId = 1, pos = pos, alive = health > 0, canFight = true } }, rng)
			for _, e in events do
				if e.kind == "telegraph" then
					table.insert(threats, { shape = e.shape, origin = e.origin, dir = e.dir, radius = e.radius, length = e.length, width = e.width, halfAngle = e.halfAngle, seen = now, interruptible = e.interruptible, attack = e.attack })
				elseif e.kind == "strike" then
					threats = {}
				elseif e.kind == "hit" and e.userId == 1 then
					health -= e.damage
					result.hits[e.attack] = (result.hits[e.attack] or 0) + 1
				end
			end
			if sim.state ~= "WINDUP" then
				threats = {} -- the telegraph is over (struck, or the attack was interrupted)
			end
			if health <= 0 then
				result.died = true
				break
			end
			if not sim.alive then
				result.won = true
				break
			end

			-- 1. get out of any telegraphed area (after a human reaction time), unless the tactic is to stand still
			local escaping = false
			local holding = false -- a telegraph is up and we are clear of it: do not walk back into it
			if not tactics.stationary then
				for _, th in threats do
					if now - th.seen >= REACTION then
						local attack = { kind = th.shape, radius = th.radius, length = th.length, width = th.width, halfAngle = th.halfAngle }
						if Sim.inArea(attack, th.origin, th.dir, pos) then
							-- interrupt instead, if this is an interruptible windup and a skill is ready
							if th.interruptible and not tactics.noSkills and (useSkill("ChargedSmash") or useSkill("ShatterWave")) then
								threats = {}
							else
								-- choose the compass direction that gets out of the area soonest (what a person does by eye)
								local bestDir, bestTime = nil, math.huge
								for i = 0, 11 do
									local a = i / 12 * math.pi * 2
									local d = V.new(math.cos(a), 0, math.sin(a))
									for tt = 0.1, 3, 0.1 do
										if not Sim.inArea(attack, th.origin, th.dir, pos + d * (RUN * tt + 1)) then
											if tt < bestTime then
												bestDir, bestTime = d, tt
											end
											break
										end
									end
								end
								stepTo(pos + (bestDir or V.new(1, 0, 0)) * 3, RUN)
							end
							escaping = true
							break
						else
							holding = true
						end
					end
				end
			end

			-- 2. otherwise fight
			if not escaping then
				local fightable = sim.state ~= "EMERGING" and sim.state ~= "TRANSITION"
				if not inReach() and not tactics.stationary and not holding then
					stepTo(V.new(sim.pos.X, 0, sim.pos.Z), RUN)
				end
				if fightable and inReach() then
					if not tactics.noSkills then
						local status = Sim.status(sim, now)
						if def.armor and status.armored then
							local _ = useSkill("ChargedSmash") or useSkill("ShatterWave")
						end
					end
					if now >= nextPunch then
						combat.nextAttackAt = now
						Combat.updateBuffs(combat, now)
						stats = Combat.stats(data, combat, now)
						local index = Combat.peekStrike(combat, now, stats.armId)
						local hit = Combat.resolveHit(stats, { family = def.family, resistance = def.resistance }, index, rng, nil)
						local r = Sim.applyDamage(sim, 1, hit.damage, { crit = hit.crit }, now)
						if not r.ignored then
							Combat.registerStrike(combat, now, stats.armId)
							punches += 1
						end
						nextPunch = now + stats.cooldown + 0.05
					end
				end
			end
		end
		result.time = now
		result.hpLeft = health
		result.punches = punches
		result.skillUses = skillUses
		return result
	end

	local function batch(creatureId, data, tactics, seeds)
		local wins, totalTime, totalHp, deaths = 0, 0, 0, 0
		local hits = {}
		for seed = 1, seeds do
			local r = fight(creatureId, data, seed * 7919, tactics)

			for k, n in r.hits do
				hits[k] = (hits[k] or 0) + n
			end
			if r.won then
				wins += 1
				totalTime += r.time
				totalHp += r.hpLeft
			end
			if r.died then
				deaths += 1
			end
		end
		return { wins = wins, deaths = deaths, hits = hits, avgTime = if wins > 0 then totalTime / wins else math.huge, avgHp = if wins > 0 then totalHp / wins else 0 }
	end

	local SEEDS = 8

	-- Loadouts a player realistically has when they reach each encounter ---------------------------------------------------------

	local starter = profile({ arm = "Starter", level = 1 })
	local stonebreaker = profile({ arm = "Stonebreaker", armLevel = 2, level = 5, skills = { ChargedSmash = 1 } })
	local alloy = profile({ arm = "Alloy", armLevel = 3, level = 10, skills = { ChargedSmash = 2, CriticalFocus = 1 } })
	local postRebirthAlloy = profile({ arm = "Alloy", armLevel = 2, level = 10, rebirths = 1, skills = { ChargedSmash = 2, CriticalFocus = 1 } })

	local function report(name, r)
		local parts = {}
		for k, n in r.hits or {} do
			table.insert(parts, k .. "=" .. n)
		end
		table.sort(parts)
		print(string.format("  [encounter] %-22s wins %d/%d (died %d)  avg %.0fs  hp left %.0f  hits taken: %s", name, r.wins, SEEDS, r.deaths, r.avgTime, r.avgHp, table.concat(parts, " ")))
	end

	t.test("the first creature can be beaten by a new player who just stands and punches", function()
		local r = batch("CairnCrawler", starter, { stationary = true, noSkills = true }, SEEDS)
		report("CairnCrawler (still)", r)
		t.truthy(r.wins >= SEEDS - 1, "a new player wins")
		t.truthy(r.avgHp >= 25, "and does not scrape through on a sliver of health")
	end)

	t.test("a normal creature is a short fight for a player with the right arm", function()
		local r = batch("CairnCrawler", starter, {}, SEEDS)
		report("CairnCrawler", r)
		t.eq(r.wins, SEEDS)
		t.truthy(r.avgTime >= 6 and r.avgTime <= 40, `{r.avgTime}s`)
		t.truthy(r.avgHp >= 70, "dodging works")
	end)

	t.test("medium creatures reward the learned skill: they are slower and more dangerous without it", function()
		local with = batch("SlagBrute", stonebreaker, {}, SEEDS)
		local without = batch("SlagBrute", stonebreaker, { noSkills = true }, SEEDS)
		report("SlagBrute (skills)", with)
		report("SlagBrute (punch only)", without)
		t.truthy(with.wins >= SEEDS - 1, "beatable with the recommended skill")
		t.truthy(with.avgTime <= 90, `{with.avgTime}s`)
		t.truthy(without.avgTime > with.avgTime * 1.3 or without.wins < with.wins, "without Charged Smash it is clearly worse")
	end)

	t.test("the large-rock elite demands its skill: punching alone does not get there", function()
		local with = batch("QuarryColossus", alloy, {}, SEEDS)
		local without = batch("QuarryColossus", alloy, { noSkills = true, maxSeconds = 240 }, SEEDS)
		report("QuarryColossus (skills)", with)
		report("QuarryColossus (punch only)", without)
		t.truthy(with.wins >= SEEDS - 2, "beatable with Charged Smash and an Alloy arm")
		t.truthy(with.avgTime >= 20 and with.avgTime <= 150, `{with.avgTime}s`)
		t.truthy(without.wins <= with.wins - 3 or without.avgTime > with.avgTime * 2, "ignoring the mechanic is not a viable shortcut")
	end)

	t.test("a stationary player cannot brute-force an elite", function()
		local r = batch("QuarryColossus", alloy, { stationary = true }, SEEDS)
		report("QuarryColossus (still)", r)
		t.truthy(r.wins <= 2)
	end)

	t.test("the first guardian is a long, mechanical fight that a prepared reborn player can win", function()
		local with = batch("GromAnvilKing", postRebirthAlloy, {}, SEEDS)
		local without = batch("GromAnvilKing", postRebirthAlloy, { noSkills = true, maxSeconds = 420 }, SEEDS)
		report("Grom (skills)", with)
		report("Grom (punch only)", without)
		t.truthy(with.wins >= SEEDS - 3, "winnable with Charged Smash, dodging and the core windows")
		t.truthy(with.avgTime >= 45 and with.avgTime <= 330, `{with.avgTime}s`)
		t.truthy(without.wins < with.wins or without.avgTime > with.avgTime * 1.5, "skills matter against the guardian")
	end)

	-- Every creature against a plausible loadout for where the player meets it ------------------------------------------------------

	-- {creature, skills the player has, rebirths, player level, band}; the arm and upgrade level come from the creature's own `fight`
	local PLAN = {
		{ "CairnCrawler", {}, 0, 1, "small" },
		{ "PrismWisp", { ChargedSmash = 1 }, 0, 5, "small" },
		{ "SlagBrute", { ChargedSmash = 1 }, 0, 5, "medium" },
		{ "QuarryColossus", { ChargedSmash = 2, CriticalFocus = 1 }, 0, 10, "elite" },
		{ "GromAnvilKing", { ChargedSmash = 2, CriticalFocus = 1 }, 1, 10, "boss" },
		-- Mossveil: reached after the first rebirth (the Forgeheart guardian's gate); its guardian wants the second
		{ "MossbackCrawler", { ChargedSmash = 1 }, 1, 6, "small" },
		{ "RootbornBrute", { ChargedSmash = 2 }, 1, 8, "medium" },
		{ "CanopyElder", { ChargedSmash = 3, CriticalFocus = 1 }, 1, 11, "elite" },
		{ "YmiraRootmother", { ChargedSmash = 3, CriticalFocus = 1, ShatterWave = 1 }, 2, 12, "boss" },
		-- Crystalfall (second rebirth to enter, third for its guardian)
		{ "Shardling", { ChargedSmash = 3, ShatterWave = 1, Overdrive = 1 }, 2, 12, "small" },
		{ "AmethystWarden", { ChargedSmash = 3, ShatterWave = 1 }, 2, 14, "medium" },
		{ "ChoirBehemoth", { ChargedSmash = 3, ShatterWave = 3 }, 2, 16, "elite" },
		{ "LyraeFrozenChorus", { ChargedSmash = 3, ShatterWave = 3 }, 3, 14, "boss" },
		-- Frostpeak mini bosses (any time after entering; the guardian above is the gate)
		{ "HoarfangYeti", { ChargedSmash = 3, ShatterWave = 3 }, 2, 14, "mini" },
		{ "GlaciermawWyrm", { ChargedSmash = 3, ShatterWave = 3 }, 2, 14, "mini" },
		{ "AvalancheTitan", { ChargedSmash = 3, ShatterWave = 3 }, 2, 14, "mini" },
		-- Emberfang (third rebirth to enter, fourth for its guardian)
		{ "AshHound", { ChargedSmash = 4, ShatterWave = 3 }, 3, 25, "small" },
		{ "MagmaGolem", { ChargedSmash = 4, ShatterWave = 3 }, 3, 26, "medium" },
		{ "ObsidianExecutioner", { ChargedSmash = 4, ShatterWave = 3 }, 3, 28, "elite" },
		{ "CinderjawSovereign", { ChargedSmash = 4, ShatterWave = 3 }, 4, 28, "boss" },
		-- Cogspire (fourth rebirth to enter, fifth for its guardian)
		{ "CogScuttler", { ChargedSmash = 4, ShatterWave = 3 }, 4, 28, "small" },
		{ "BoilerBrute", { ChargedSmash = 4, ShatterWave = 3 }, 4, 28, "medium" },
		{ "BrassBehemoth", { ChargedSmash = 4, ShatterWave = 3 }, 4, 29, "elite" },
		{ "CogheartEngine", { ChargedSmash = 4, ShatterWave = 3 }, 5, 30, "boss" },
		-- Dustwake (fifth rebirth to enter, sixth for its guardian)
		{ "DuneSkitterer", { ChargedSmash = 4, ShatterWave = 3 }, 5, 30, "small" },
		{ "HuskSentinel", { ChargedSmash = 4, ShatterWave = 3 }, 5, 30, "medium" },
		{ "TombColossus", { ChargedSmash = 4, ShatterWave = 3 }, 5, 30, "elite" },
		{ "OszarakBuriedSovereign", { ChargedSmash = 4, ShatterWave = 3 }, 6, 30, "boss" },
	}
	for _, entry in PLAN do
		local def = Creatures.Defs[entry[1]]
		entry[6] = profile({ arm = def.fight.arm, armLevel = def.fight.level, level = entry[4], rebirths = entry[3], skills = entry[2] })
	end
	local BANDS = { small = { 6, 40 }, medium = { 15, 70 }, elite = { 35, 130 }, mini = { 45, 200 }, boss = { 80, 320 } }

	t.test("every creature is a fair, appropriately long fight for a player with the matching arm and skills", function()
		local problems = {}
		for _, entry in PLAN do
			local id, data, band = entry[1], entry[6], entry[5]
			local r = batch(id, data, {}, SEEDS)
			report(id, r)
			local lo, hi = BANDS[band][1], BANDS[band][2]
			if r.wins < SEEDS - 2 then
				table.insert(problems, `{id}: only {r.wins}/{SEEDS} wins`)
			elseif r.avgTime < lo or r.avgTime > hi then
				table.insert(problems, `{id}: {math.floor(r.avgTime)}s is outside {lo}-{hi}s`)
			end
		end
		t.eq(table.concat(problems, "; "), "")
	end)

	t.test("no creature's armor lets plain punching stand in for its breaker skill", function()
		for _, entry in PLAN do
			local id, data = entry[1], entry[6]
			local def = Creatures.Defs[id]
			if def.armor and def.armor.mult <= 0.2 then
				local skilled = batch(id, data, {}, 4)
				local punchOnly = batch(id, data, { noSkills = true, maxSeconds = 480 }, 4)
				report(id .. " (punch only)", punchOnly)
				t.truthy(punchOnly.wins == 0 or punchOnly.avgTime > skilled.avgTime * 4, id .. ": punching alone must be several times slower than using the skill")
			end
		end
	end)
end
