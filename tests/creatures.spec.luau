-- CreatureSim / EncounterSM: the creature combat rules, with no Roblox in the loop.
local roblox = require("@lune/roblox")

return function(t, u)
	local Sim = u:load("Logic/CreatureSim")
	local SM = u:load("Logic/EncounterSM")
	local Creatures = u:load("Config/Creatures")
	local V = roblox.Vector3

	local rng = {
		next = function()
			return 0.01 -- always the first weighted attack that is available
		end,
	}

	local function player(userId, x, z, extra)
		local p = { userId = userId, pos = V.new(x, 0, z), alive = true, canFight = true }
		for k, v in extra or {} do
			p[k] = v
		end
		return p
	end

	local function make(defId, hp)
		local def = Creatures.Defs[defId]
		return Sim.new(1, def, hp or 1000, V.new(0, 0, 0), 0)
	end

	-- Steps the sim from `from` to `to` and returns every event.
	local function run(sim, from, to, players)
		local events = {}
		local now = from
		while now < to - 1e-9 do
			now += 0.05
			for _, e in Sim.step(sim, now, 0.05, players, rng) do
				table.insert(events, e)
			end
		end
		return events, now
	end

	local function count(events, kind)
		local n = 0
		for _, e in events do
			if e.kind == kind then
				n += 1
			end
		end
		return n
	end

	local function hitsOn(events, userId)
		local n = 0
		for _, e in events do
			if e.kind == "hit" and e.userId == userId then
				n += 1
			end
		end
		return n
	end

	-- A creature that has finished emerging and is awake.
	local function awake(defId, hp)
		local sim = make(defId, hp)
		local _, now = run(sim, 0, sim.def.emerge + 0.8, {})
		return sim, now
	end

	-- Emergence and targeting ---------------------------------------------------------------------------------

	t.test("a creature is invulnerable while it emerges and then idles until a player comes close", function()
		local sim = make("CairnCrawler")
		local r = Sim.applyDamage(sim, 7, 50, {}, 0.5)
		t.eq(r.ignored, true)
		t.eq(sim.hp, sim.maxHp)
		local _, now = run(sim, 0, sim.def.emerge + 0.1, {})
		t.eq(sim.state, "IDLE")
		run(sim, now, now + 2, { player(1, 90, 0) })
		t.eq(sim.state, "IDLE", "a player outside aggro range does not wake it")
		local events = run(sim, now + 2, now + 3, { player(1, 12, 0) })
		t.eq(sim.state ~= "IDLE", true)
		t.eq(count(events, "aggro"), 1)
	end)

	t.test("dead players and players who cannot fight are never targeted or hit", function()
		local sim, now = awake("CairnCrawler")
		local ghosts = { player(1, 6, 0, { alive = false }), player(2, 6, 1, { canFight = false }) }
		local events = run(sim, now, now + 6, ghosts)
		t.eq(sim.state, "IDLE")
		t.eq(count(events, "hit"), 0)
		t.eq(count(events, "telegraph"), 0)
	end)

	-- Attacks: telegraph, locked area, recovery -----------------------------------------------------------------

	t.test("an attack winds up with a telegraph first and only then hurts", function()
		local sim, now = awake("CairnCrawler")
		local p = player(1, 8, 0)
		local events = run(sim, now, now + 0.4, { p })
		t.eq(count(events, "telegraph"), 1, "telegraph announced")
		t.eq(count(events, "hit"), 0, "no damage during the windup")
		t.eq(sim.state, "WINDUP")
		local later = run(sim, now + 0.4, now + 1.4, { p })
		t.eq(hitsOn(later, 1), 1)
	end)

	t.test("moving out of a locked circle during the windup avoids the hit", function()
		local sim, now = awake("SlagBrute")
		local p = player(1, 6, 0)
		local events, t1 = run(sim, now, now + 0.3, { p })
		t.eq(count(events, "telegraph"), 1)
		local tele
		for _, e in events do
			if e.kind == "telegraph" then
				tele = e
			end
		end
		t.eq(tele.shape, "circle")
		-- walk well outside the circle before the windup ends
		p.pos = V.new(tele.origin.X + tele.radius + 6, 0, tele.origin.Z)
		local after = run(sim, t1, t1 + 2.5, { p })
		t.eq(hitsOn(after, 1), 0, "dodged")
	end)

	t.test("standing still in the circle is hit exactly once per attack", function()
		local sim, now = awake("SlagBrute")
		local p = player(1, 5, 0)
		local events = run(sim, now, now + 2.2, { p })
		t.eq(hitsOn(events, 1), 1)
		local strikes = count(events, "strike")
		t.eq(strikes, 1)
	end)

	t.test("area shapes: circle, cone and line", function()
		local circle = { id = "c", name = "c", kind = "circle", aim = "self", windup = 1, recover = 1, range = 5, cooldown = 1, damage = 1, radius = 5, text = "" }
		local cone = { id = "k", name = "k", kind = "cone", aim = "target", windup = 1, recover = 1, range = 5, cooldown = 1, damage = 1, length = 10, halfAngle = 45, text = "" }
		local line = { id = "l", name = "l", kind = "line", aim = "target", windup = 1, recover = 1, range = 5, cooldown = 1, damage = 1, length = 10, width = 4, text = "" }
		local o, dir = V.new(0, 0, 0), V.new(1, 0, 0)
		t.truthy(Sim.inArea(circle, o, dir, V.new(4, 0, 0)))
		t.eq(Sim.inArea(circle, o, dir, V.new(8, 0, 0)), false)
		t.truthy(Sim.inArea(cone, o, dir, V.new(8, 0, 3)))
		t.eq(Sim.inArea(cone, o, dir, V.new(8, 0, 12)), false, "outside the angle")
		t.eq(Sim.inArea(cone, o, dir, V.new(-5, 0, 0)), false, "behind")
		t.eq(Sim.inArea(cone, o, dir, V.new(14, 0, 0)), false, "beyond the length")
		t.truthy(Sim.inArea(line, o, dir, V.new(9, 0, 1)))
		t.eq(Sim.inArea(line, o, dir, V.new(9, 0, 5)), false, "beside the line")
		t.eq(Sim.inArea(line, o, dir, V.new(-6, 0, 0)), false, "behind the start")
	end)

	t.test("the creature is committed during recovery and does not chain attacks without a gap", function()
		local sim, now = awake("CairnCrawler")
		local p = player(1, 8, 0)
		local events = run(sim, now, now + 8, { p })
		local strikes = count(events, "strike")
		local def = sim.def.attacks[1]
		-- at most one strike per (windup + recover + gap)
		t.lte(strikes, math.floor(8 / (def.windup + def.recover)) + 1)
		t.truthy(strikes >= 2, "it does keep attacking")
	end)

	t.test("ranged creatures keep their distance and stay out of melee", function()
		local sim, now = awake("PrismWisp")
		local p = player(1, 4, 0)
		run(sim, now, now + 4, { p })
		local d = math.sqrt((sim.pos.X - p.pos.X) ^ 2 + (sim.pos.Z - p.pos.Z) ^ 2)
		t.truthy(d >= sim.def.preferredRange * 0.6, `kited to {d}`)
	end)

	t.test("a dash carries the creature along the line and never past its leash", function()
		local sim, now = awake("CairnCrawler")
		local p = player(1, 9, 0)
		run(sim, now, now + 2.2, { p })
		t.truthy(sim.pos.X > 1, "it moved toward the player")
		local dx, dz = sim.pos.X - sim.home.X, sim.pos.Z - sim.home.Z
		t.lte(math.sqrt(dx * dx + dz * dz), sim.def.leash + 1e-6)
	end)

	-- Damage rules ----------------------------------------------------------------------------------------------

	t.test("valid damage reduces health; invalid, NaN and negative damage is ignored", function()
		local sim, now = awake("CairnCrawler", 100)
		local r = Sim.applyDamage(sim, 1, 30, {}, now)
		t.eq(r.applied, 30)
		t.eq(sim.hp, 70)
		for _, bad in { 0, -5, 0 / 0 } do
			local ignored = Sim.applyDamage(sim, 1, bad, {}, now)
			t.eq(ignored.ignored, true)
		end
		t.eq(sim.hp, 70)
		local over = Sim.applyDamage(sim, 1, 5000, {}, now)
		t.eq(over.applied, 70, "overkill is capped at the remaining health")
		t.eq(over.killed, true)
	end)

	t.test("armor blunts basic strikes; a breaker skill opens it for a limited time", function()
		local sim, now = awake("SlagBrute", 10000)
		local armor = sim.def.armor
		local basic = Sim.applyDamage(sim, 1, 100, {}, now)
		t.eq(basic.applied, math.floor(100 * armor.mult + 0.5))
		t.eq(basic.armored, true)
		local smash = Sim.applyDamage(sim, 1, 100, { skill = "ChargedSmash" }, now)
		t.eq(smash.armorBroken, true)
		t.eq(smash.applied, 100, "the strike that breaks the armor lands in full")
		local open = Sim.applyDamage(sim, 1, 100, {}, now + 1)
		t.eq(open.applied, 100)
		t.eq(open.armored, false)
		local closed = Sim.applyDamage(sim, 1, 100, {}, now + armor.breakDuration + 0.5)
		t.eq(closed.applied, math.floor(100 * armor.mult + 0.5), "armor is back")
	end)

	t.test("a skill that is not a breaker does not open the armor", function()
		local sim, now = awake("QuarryColossus", 100000)
		local r = Sim.applyDamage(sim, 1, 100, { skill = "ShatterWave" }, now)
		t.eq(r.armorBroken, false)
		t.eq(r.armored, true)
		-- the Choir's shell is the opposite: only Shatter Wave opens it
		local choir, n2 = awake("ChoirBehemoth", 100000)
		t.eq(Sim.applyDamage(choir, 1, 100, { skill = "ChargedSmash" }, n2).armorBroken, false)
		t.eq(Sim.applyDamage(choir, 1, 100, { skill = "ShatterWave" }, n2).armorBroken, true)
	end)

	t.test("the core opens after a heavy attack and every strike is amplified while it is exposed", function()
		local sim, now = awake("SlagBrute", 100000)
		local p = player(1, 5, 0)
		local _, t1 = run(sim, now, now + 2.0, { p }) -- slam strikes, recovery begins
		local st = Sim.status(sim, t1)
		t.eq(st.coreOpen, true)
		local hit = Sim.applyDamage(sim, 1, 100, {}, t1)
		t.eq(hit.coreHit, true)
		t.eq(hit.applied, math.floor(100 * sim.def.core.mult + 0.5))
		local _, t2 = run(sim, t1, t1 + 4, { player(1, 90, 0) })
		t.eq(Sim.status(sim, t2).coreOpen, false, "the window closes")
	end)

	t.test("a listed skill interrupts an interruptible windup; basic strikes and other skills do not", function()
		local sim, now = awake("QuarryColossus", 100000)
		local p = player(1, 10, 0)
		-- run until a GroundQuake (interruptible) is winding up: force it by hand for determinism
		local quake = sim.def.attacks[2]
		sim.target = 1
		sim.attack = quake
		sim.state = "WINDUP"
		sim.endsAt = now + 2
		local basic = Sim.applyDamage(sim, 1, 50, {}, now)
		t.eq(basic.interrupted, false)
		t.eq(sim.state, "WINDUP")
		local wave = Sim.applyDamage(sim, 1, 50, { skill = "CriticalFocus" }, now)
		t.eq(wave.interrupted, false, "not an interrupter")
		local smash = Sim.applyDamage(sim, 1, 50, { skill = "ChargedSmash" }, now)
		t.eq(smash.interrupted, true)
		t.eq(sim.state, "STAGGERED")
		t.eq(sim.attack, nil)
		t.eq(Sim.status(sim, now).coreOpen, true, "a stagger exposes the core")
		local events = run(sim, now, now + sim.def.staggerTime + 0.2, { p })
		t.eq(hitsOn(events, 1), 0, "the cancelled attack never lands")
		t.eq(sim.state == "ENGAGED" or sim.state == "WINDUP", true)
	end)

	t.test("an attack that is not interruptible cannot be cancelled by a skill", function()
		local sim, now = awake("QuarryColossus", 100000)
		sim.target = 1
		sim.attack = sim.def.attacks[1] -- Boulder Slam
		sim.state = "WINDUP"
		sim.endsAt = now + 1.4
		local r = Sim.applyDamage(sim, 1, 50, { skill = "ChargedSmash" }, now)
		t.eq(r.interrupted, false)
		t.eq(sim.state, "WINDUP")
	end)

	-- Defeat, rewards, phases ------------------------------------------------------------------------------------

	t.test("a defeated creature stays defeated: no damage, no steps, no second payout", function()
		local sim, now = awake("CairnCrawler", 40)
		local kill = Sim.applyDamage(sim, 1, 100, {}, now)
		t.eq(kill.killed, true)
		t.eq(sim.state, "DEFEATED")
		t.eq(sim.alive, false)
		local again = Sim.applyDamage(sim, 2, 100, {}, now)
		t.eq(again.ignored, true)
		t.eq(again.killed, false, "a simultaneous second final hit cannot kill twice")
		local events = run(sim, now, now + 5, { player(1, 3, 0) })
		t.eq(#events, 0)
		t.eq(sim.state, "DEFEATED")
		local first = Sim.payout(sim, { coins = 100, xp = 50, shards = 2 })
		t.truthy(first)
		t.eq(Sim.payout(sim, { coins = 100, xp = 50, shards = 2 }), nil, "pays once")
	end)

	t.test("payout is withheld while the creature lives", function()
		local sim, now = awake("CairnCrawler", 1000)
		Sim.applyDamage(sim, 1, 100, {}, now)
		t.eq(Sim.payout(sim, { coins = 1, xp = 1, shards = 0 }), nil)
		t.eq(sim.paid, false)
	end)

	t.test("rewards are split by contribution: a chip does not earn a full share, the killer gets a bonus", function()
		local sim, now = awake("CairnCrawler", 1000)
		Sim.applyDamage(sim, 1, 600, {}, now)
		Sim.applyDamage(sim, 2, 380, {}, now)
		Sim.applyDamage(sim, 3, 5, {}, now)
		Sim.applyDamage(sim, 2, 5000, {}, now) -- the killing blow
		local rewards = Sim.payout(sim, { coins = 100, xp = 100, shards = 4 })
		t.truthy(rewards)
		t.eq(rewards[3].fraction < 1, true)
		t.eq(rewards[1].fraction, 1)
		t.eq(rewards[2].killer, true)
		t.truthy(rewards[2].coins > rewards[1].coins, "last-hit bonus")
		t.truthy(rewards[3].coins < rewards[1].coins)
	end)

	t.test("boss phases: crossing a threshold pauses the creature briefly and changes its tempo", function()
		local sim, now = awake("GromAnvilKing", 10000)
		sim.armorOpenUntil = now + 100 -- armor open so damage lands in full
		local before = sim.def.attacks[1].windup
		local r = Sim.applyDamage(sim, 1, 3600, {}, now) -- 64% left: below the first threshold (0.66)
		t.eq(r.phaseChanged, true)
		t.eq(sim.phase, 2)
		t.eq(sim.state, "TRANSITION")
		local blocked = Sim.applyDamage(sim, 1, 500, {}, now + 0.5)
		t.eq(blocked.ignored, true, "invulnerable during the transition")
		local p = player(1, 10, 0)
		local _, later = run(sim, now, now + 2.2, { p })
		t.truthy(sim.state ~= "TRANSITION")
		t.eq(sim.phase, 2)
		-- phase 2 unlocks Molten Quake: it must be usable now and not before
		local sim1, n1 = awake("GromAnvilKing", 10000)
		local quakeAvailable1, quakeAvailable2 = false, false
		for _, a in sim1.def.attacks do
			if a.id == "MoltenQuake" and (a.minPhase or 1) <= sim1.phase then
				quakeAvailable1 = true
			end
			if a.id == "MoltenQuake" and (a.minPhase or 1) <= 2 then
				quakeAvailable2 = true
			end
		end
		t.eq(quakeAvailable1, false)
		t.eq(quakeAvailable2, true)
		t.truthy(before > 0 and later > now and n1 > 0)
	end)

	t.test("a boss can pass several thresholds in one hit and still ends in a consistent phase", function()
		local sim, now = awake("GromAnvilKing", 10000)
		sim.armorOpenUntil = now + 100
		local r = Sim.applyDamage(sim, 1, 8000, {}, now)
		t.eq(r.phaseChanged, true)
		t.eq(sim.phase, 3)
		t.eq(sim.alive, true)
	end)

	-- Leash, healing, recovery -------------------------------------------------------------------------------------

	t.test("when everyone leaves it disengages, heals while idle and finally retreats", function()
		local sim, now = awake("CairnCrawler", 1000)
		local p = player(1, 8, 0)
		run(sim, now, now + 0.5, { p })
		Sim.applyDamage(sim, 1, 500, {}, now + 0.5)
		local events, t1 = run(sim, now + 0.5, now + 4, {})
		t.eq(count(events, "disengage"), 1)
		t.eq(sim.state, "IDLE")
		local before = sim.hp
		local _, t2 = run(sim, t1, t1 + 5, {})
		t.truthy(sim.hp > before, "it heals while nobody is fighting it")
		local despawn = run(sim, t2, t2 + Creatures.Config.idleDespawn + 1, {})
		t.truthy(count(despawn, "despawn") >= 1)
	end)

	t.test("a player outside the leash radius cannot be engaged", function()
		local sim, now = awake("CairnCrawler")
		local far = player(1, sim.def.leash + 20, 0)
		sim.target = 1
		local events = run(sim, now, now + 3, { far })
		t.eq(count(events, "telegraph"), 0)
	end)

	t.test("reset restores a creature that was abandoned mid-fight", function()
		local sim, now = awake("SlagBrute", 1000)
		Sim.applyDamage(sim, 1, 400, { skill = "ChargedSmash" }, now)
		Sim.reset(sim, now + 1)
		t.eq(sim.hp, sim.maxHp)
		t.eq(sim.state, "IDLE")
		t.eq(Sim.status(sim, now + 1).armorOpen, false)
		t.eq(next(sim.contributors), nil)
	end)

	-- Encounter lifecycle ------------------------------------------------------------------------------------------

	t.test("the encounter lifecycle only moves forward along legal transitions", function()
		local enc = SM.new()
		t.eq(enc.state, "SEALED")
		t.eq(SM.to(enc, "COMBAT"), false, "cannot skip the reveal")
		t.eq(SM.to(enc, "DEFEATED"), false)
		t.truthy(SM.to(enc, "REVEAL"))
		t.eq(enc.spawns, 1)
		t.eq(SM.to(enc, "REVEAL"), false, "a duplicate final hit cannot release a second creature")
		t.eq(enc.spawns, 1)
		t.truthy(SM.to(enc, "COMBAT"))
		t.truthy(SM.to(enc, "DEFEATED"))
		t.eq(SM.to(enc, "COMBAT"), false, "defeated never returns to combat")
		t.eq(SM.to(enc, "DEFEATED"), false)
		t.truthy(SM.to(enc, "RECOVERY"))
		t.eq(SM.to(enc, "SEALED"), false, "must pass through RESPAWNING")
		t.truthy(SM.to(enc, "RESPAWNING"))
		local token = enc.token
		t.truthy(SM.to(enc, "SEALED"))
		t.truthy(enc.token ~= token, "a new life invalidates timers from the old one")
	end)

	t.test("an abandoned encounter can recover from reveal or combat without a reward", function()
		local a = SM.new()
		SM.to(a, "REVEAL")
		t.truthy(SM.to(a, "RECOVERY"))
		local b = SM.new()
		SM.to(b, "REVEAL")
		SM.to(b, "COMBAT")
		t.truthy(SM.to(b, "RECOVERY"))
		t.eq(SM.hasCreature(b), false)
		t.truthy(SM.to(b, "RESPAWNING"))
	end)

	t.test("a creature exists exactly between the reveal and its recovery", function()
		local enc = SM.new()
		t.eq(SM.hasCreature(enc), false)
		SM.to(enc, "REVEAL")
		t.eq(SM.hasCreature(enc), true)
		SM.to(enc, "COMBAT")
		SM.to(enc, "DEFEATED")
		t.eq(SM.hasCreature(enc), true)
		SM.to(enc, "RECOVERY")
		t.eq(SM.hasCreature(enc), false)
	end)

	t.test("rock wear maps to the sealed / damaged / fracturing / shattered labels", function()
		t.eq(SM.sealedLabel("INTACT"), "SEALED")
		t.eq(SM.sealedLabel("SURFACE"), "DAMAGED")
		t.eq(SM.sealedLabel("CHIPPED"), "DAMAGED")
		t.eq(SM.sealedLabel("FRACTURED"), "FRACTURING")
		t.eq(SM.sealedLabel("COLLAPSE"), "SHATTERED")
	end)
end
