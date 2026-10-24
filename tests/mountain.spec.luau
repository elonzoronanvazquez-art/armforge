-- Frostpeak Mountain mechanics: Summit Momentum, climbing routes, the tramway schedule, mini bosses and the config that ties them together.
local roblox = require("@lune/roblox")
local ServerWorld = require("./support/ServerWorld")

return function(t, u)
	local Momentum = u:load("Logic/Momentum")
	local Climb = u:load("Logic/Climb")
	local Tram = u:load("Logic/Tram")
	local Guardians = u:load("Logic/Guardians")
	local Schema = u:load("Logic/DataSchema")
	local Mountain = u:load("Config/Mountain")
	local IslandCfg = u:load("Config/Islands")
	local Creatures = u:load("Config/Creatures")
	local Rocks = u:load("Config/Rocks")
	local V = roblox.Vector3

	-- Momentum ------------------------------------------------------------------------------------------------------------------

	t.test("Frostpeak grants +50% XP and +7% coins for five minutes, and no other island grants anything", function()
		local cfg = IslandCfg.Defs.Crystalfall.momentum
		t.near(cfg.xp, 1.5, 1e-9)
		t.near(cfg.coins, 1.07, 1e-9)
		t.eq(cfg.seconds, 300)
		t.eq(Momentum.text("Crystalfall"), "+50% XP, +7% coins")
		for id, def in IslandCfg.Defs do
			if id ~= "Crystalfall" then
				t.eq(def.momentum, nil, id)
				t.eq(Momentum.grant({}, id, 0), false, id)
			end
		end
	end)

	t.test("momentum boosts only the island that granted it, only until it expires, and refreshes", function()
		local holder = {}
		t.eq(Momentum.multipliers(holder, "Crystalfall", 0).xp, 1, "nothing before a feat")
		t.truthy(Momentum.grant(holder, "Crystalfall", 100))
		t.near(Momentum.multipliers(holder, "Crystalfall", 150).xp, 1.5, 1e-9)
		t.near(Momentum.multipliers(holder, "Crystalfall", 150).coins, 1.07, 1e-9)
		t.eq(Momentum.multipliers(holder, "Forgeheart", 150).xp, 1, "not on other islands")
		t.eq(Momentum.multipliers(holder, "Emberfang", 150).coins, 1)
		t.near(Momentum.remaining(holder, 150), 250, 1e-9)
		t.eq(Momentum.multipliers(holder, "Crystalfall", 400).xp, 1, "expired at 400")
		t.eq(Momentum.remaining(holder, 500), 0)
		Momentum.grant(holder, "Crystalfall", 390)
		t.near(Momentum.remaining(holder, 390), 300, 1e-9, "a new feat refreshes the timer, it does not stack")
		t.near(Momentum.multipliers(holder, "Crystalfall", 391).xp, 1.5, 1e-9)
	end)

	t.test("momentum is transient: it is never part of the saved profile", function()
		local d = Schema.default()
		t.eq(d.momentum, nil)
		t.eq(Schema.snapshot(d).momentum, nil)
	end)

	-- Climbing ------------------------------------------------------------------------------------------------------------------

	local route = { id = "Test", base = V.new(0, 48, 0), top = V.new(0, 94, 0), minSeconds = 2.6 }

	local function climbTo(progress, fromT, toT, step, t0, dt)
		local ev
		local now = t0
		local f = fromT
		while f < toT do
			f = math.min(toT, f + step)
			now += dt
			progress, ev = Climb.step(progress, route, V.new(0.5, 48 + 46 * f, 0), now)
			if ev == "complete" then
				return progress, ev, now
			end
		end
		return progress, ev, now
	end

	t.test("an honest climb begins at the foot and completes near the top", function()
		local p, ev = Climb.step(nil, route, V.new(0.5, 48.5, 0), 0)
		t.eq(ev, "begin")
		local done
		p, done = climbTo(p, 0, 1, 0.07, 0, 0.25)
		t.eq(done, "complete")
		t.eq(p, nil)
	end)

	t.test("walking past, standing at the top or being far from the route is not a climb", function()
		local p, ev = Climb.step(nil, route, V.new(30, 48.5, 0), 0)
		t.eq(p, nil)
		t.eq(ev, nil)
		p, ev = Climb.step(nil, route, V.new(0.5, 93, 0), 0)
		t.eq(p, nil, "arriving at the top by another way (tram, jump) never starts a climb")
		t.eq(ev, nil)
		p, ev = Climb.step(nil, route, V.new(0.5, 70, 0), 0)
		t.eq(p, nil, "mid-wall without a start does not count")
	end)

	t.test("a teleport up the wall, or climbing impossibly fast, never pays", function()
		local p = Climb.step(nil, route, V.new(0.5, 48.5, 0), 0)
		local ev
		p, ev = Climb.step(p, route, V.new(0.5, 93, 0), 0.25)
		t.eq(p, nil, "a jump of nearly the whole route resets")
		t.eq(ev, nil)
		-- steady but faster than minSeconds: the completion waits for the fastest honest time
		p = Climb.step(nil, route, V.new(0.5, 48.5, 0), 10)
		local early
		p, early = climbTo(p, 0, 1, 0.1, 10, 0.1)
		t.eq(early, nil, "10 samples of 0.1s is 1s, under the 2.6s minimum")
		t.truthy(p ~= nil, "still on the route, waiting")
		local _, done = Climb.step(p, route, V.new(0.5, 94, 0), 10 + 2.7)
		t.eq(done, "complete", "and it counts once the minimum time has passed")
	end)

	t.test("falling off or leaving the route resets the climb; taking forever times out", function()
		local p = Climb.step(nil, route, V.new(0.5, 48.5, 0), 0)
		p = Climb.step(p, route, V.new(0.5, 60, 0), 1)
		t.truthy(p)
		local after, ev = Climb.step(p, route, V.new(12, 60, 0), 2)
		t.eq(after, nil)
		t.eq(ev, nil)
		local q = Climb.step(nil, route, V.new(0.5, 48.5, 0), 0)
		local timedOut = Climb.step(q, route, V.new(0.5, 55, 0), Mountain.Climb.maxSeconds + 1)
		t.eq(timedOut, nil)
	end)

	t.test("climbing routes are distinct, spaced around the crown and have a sane minimum time", function()
		local seen = {}
		for _, r in Mountain.Routes do
			t.eq(seen[r.id], nil, r.id)
			seen[r.id] = true
			t.truthy(r.minSeconds >= 1 and r.minSeconds <= 10, r.id)
		end
		t.eq(#Mountain.Routes, 3)
		for i = 1, #Mountain.Routes do
			for j = i + 1, #Mountain.Routes do
				local d = math.abs(Mountain.Routes[i].angle - Mountain.Routes[j].angle) % 360
				t.truthy(math.min(d, 360 - d) >= 45, "routes are well apart")
			end
		end
		t.truthy(Mountain.SlopeLimit < 89 and Mountain.SlopeLimit >= 45)
	end)

	-- Tramway -------------------------------------------------------------------------------------------------------------------

	t.test("the tram schedule: both cabins dock together, swap ends smoothly and repeat", function()
		local cfg = Mountain.Tram
		local s = Tram.state(0)
		t.eq(s.docked, true)
		t.eq(s.baseCabin, 1)
		t.eq(s.summitCabin, 2)
		t.near(s.departsIn, cfg.dock, 1e-9)
		t.eq(Tram.position(s, 1), 0)
		t.eq(Tram.position(s, 2), 1)
		-- mid travel: cabin 1 rising, cabin 2 falling, always complementary
		local mid = Tram.state(cfg.dock + cfg.travel / 2)
		t.eq(mid.docked, false)
		t.near(mid.cabin1, 0.5, 1e-9)
		t.near(mid.cabin1 + mid.cabin2, 1, 1e-9)
		t.eq(mid.baseCabin, nil)
		-- the second leg starts with cabin 1 at the summit, cabin 2 at the base
		local leg2 = Tram.state(cfg.dock + cfg.travel + 0.1)
		t.eq(leg2.leg, 2)
		t.eq(leg2.baseCabin, 2)
		t.eq(leg2.summitCabin, 1)
		t.eq(Tram.position(leg2, 1), 1)
		-- periodic
		local a, b = Tram.state(7.3), Tram.state(7.3 + Tram.cycle())
		t.near(a.cabin1, b.cabin1, 1e-9)
		t.eq(a.docked, b.docked)
	end)

	t.test("cabin positions are continuous and monotonic in each leg", function()
		local cfg = Mountain.Tram
		local last = 0
		local x = cfg.dock
		while x <= cfg.dock + cfg.travel do
			local p = Tram.state(x).cabin1
			t.truthy(p >= last - 1e-9, "cabin 1 only rises during leg 1")
			t.truthy(p >= 0 and p <= 1)
			last = p
			x += 0.25
		end
		t.near(Tram.state(cfg.dock + cfg.travel - 1e-6).cabin1, 1, 1e-3)
		t.near(Tram.state(cfg.dock + cfg.travel + 1e-6).cabin1, 1, 1e-9, "no jump at arrival")
	end)

	t.test("boarding needs a docked cabin, time before departure and room", function()
		local cfg = Mountain.Tram
		local cabin, why = Tram.canBoard(Tram.state(0), "base", 0)
		t.eq(cabin, 1)
		t.eq(why, nil)
		t.eq(Tram.canBoard(Tram.state(0), "summit", 0), 2)
		t.eq(Tram.canBoard(Tram.state(cfg.dock + 2), "base", 0), nil, "between stations")
		t.eq(Tram.canBoard(Tram.state(cfg.dock - 0.5), "base", 0), nil, "about to leave")
		t.eq(Tram.canBoard(Tram.state(0), "base", cfg.capacity), nil, "full")
		local second = Tram.state(cfg.dock + cfg.travel + 1)
		t.eq(Tram.canBoard(second, "base", 0), 2, "the other cabin serves the base on the second leg")
		t.eq(Tram.canBoard(second, "summit", 0), 1)
	end)

	-- Mini bosses and the island config ----------------------------------------------------------------------------------------

	t.test("Frostpeak has exactly three mini bosses with their own seals, in reach of the plateau and inside the island", function()
		local isl = IslandCfg.Defs.Crystalfall
		t.eq(#isl.miniBosses, 3)
		local seen = {}
		for _, m in isl.miniBosses do
			local c, seal = Creatures.Defs[m.creature], Rocks.Defs[m.seal]
			t.truthy(c and seal, m.creature)
			t.eq(c.mini, true)
			t.eq(c.tier, "boss")
			t.eq(c.island, "Crystalfall")
			t.eq(seal.encounter, m.creature)
			t.eq(seal.size, "seal")
			t.eq(seen[m.seal], nil, "unique seals")
			seen[m.seal] = true
			local flat = (V.new(m.position.X, 0, m.position.Z) - V.new(isl.center.X, 0, isl.center.Z)).Magnitude
			t.truthy(flat < isl.radius * 0.8, m.creature .. " stands on the island")
			t.truthy(c.attacks and #c.attacks >= 3 and c.phases and #c.phases >= 1 and c.armor and c.core, m.creature .. " has real mechanics")
		end
		-- the mini bosses are not the guardian and never take its slot
		for _, m in isl.miniBosses do
			t.truthy(m.creature ~= isl.guardian.creature and m.seal ~= isl.guardian.seal)
		end
		-- and only Frostpeak has any
		for id, def in IslandCfg.Defs do
			if id ~= "Crystalfall" then
				t.eq(def.miniBosses, nil, id)
			end
		end
	end)

	t.test("a mini boss needs island access and its own rebirths, and never completes the island", function()
		local d = Schema.default()
		t.eq(Guardians.canChallengeMini(d, "Crystalfall", "HoarfangYeti").ok, false)
		t.deepEq(Guardians.canChallengeMini(d, "Crystalfall", "HoarfangYeti").missing, { "Access to the island", "Rebirth 2" })
		d.islands.unlocked.Crystalfall = true
		d.rebirths = 2
		t.eq(Guardians.canChallengeMini(d, "Crystalfall", "HoarfangYeti").ok, true)
		t.eq(Guardians.canChallengeMini(d, "Crystalfall", "LyraeFrozenChorus").err, "no_mini_boss", "the guardian is not a mini boss")
		t.eq(Guardians.canChallengeMini(d, "Forgeheart", "HoarfangYeti").err, "no_mini_boss")
		t.eq(Guardians.defeated(d, "Crystalfall"), false)
	end)

	-- Server integration ---------------------------------------------------------------------------------------------------------

	local function setup(userId)
		local world = ServerWorld.new()
		local svc = world:boot({ encounters = true })
		local player = world:join(userId or 701)
		return world, svc, player, svc.Sessions.get(player)
	end

	local function notifies(world, player, kind)
		local n = 0
		for _, args in world:sent("Notify", player) do
			if args[1] == kind then
				n += 1
			end
		end
		return n
	end

	local function lastReward(world, player, kind)
		local found
		for _, args in world:sent("Notify", player) do
			if args[1] == kind then
				found = args[2]
			end
		end
		return found
	end

	t.test("rock rewards on Frostpeak are boosted by momentum, and only then", function()
		local world, svc, player, session = setup(710)
		world:placeCharacter(player, V.new(0, 3, 30))
		local function kill(x)
			world:placeCharacter(player, V.new(x, 3, 30))
			local rock = svc.RockService.spawnAt("Quartz", V.new(x, 0, 40), "Crystalfall")
			svc.RockService.damage(rock, player, player.UserId, rock.state.maxHp * 2, {})
			return lastReward(world, player, "Reward")
		end
		local plain = kill(0)
		Momentum.grant(session, "Crystalfall", 0)
		local boosted = kill(40)
		t.near(boosted.xp, plain.xp * 1.5, 1.01)
		t.near(boosted.coins, plain.coins * 1.07, 1.01)
		t.truthy(boosted.xp > plain.xp)
		-- a rock on another island is untouched by Frostpeak's momentum
		world:placeCharacter(player, V.new(80, 3, 30))
		local other = svc.RockService.spawnAt("Quartz", V.new(80, 0, 40), "Forgeheart")
		svc.RockService.damage(other, player, player.UserId, other.state.maxHp * 2, {})
		t.eq(lastReward(world, player, "Reward").xp, plain.xp)
		-- expired
		session.momentum = { island = "Crystalfall", untilT = -1 }
		t.eq(kill(120).xp, plain.xp)
		world:assertNoErrors()
	end)

	t.test("a mini boss opens only for eligible players, pays out, and completes nothing", function()
		local world, svc, player, session = setup(720)
		local seal = svc.RockService.spawnAt("HoarSeal", V.new(0, 0, 40), "Crystalfall")
		world:placeCharacter(player, seal.base.Position + V.new(10, 3, 0))
		-- locked out: no island access, no rebirths
		t.eq(svc.RockService.damage(seal, player, player.UserId, 1e9, {}), nil, "an ineligible player cannot even hurt the seal")
		session.data.islands.unlocked.Crystalfall = true
		t.eq(svc.RockService.damage(seal, player, player.UserId, 1e9, {}), nil, "island access alone is not enough")
		session.data.rebirths = 2
		local coins = session.data.coins
		t.truthy(svc.RockService.damage(seal, player, player.UserId, seal.state.maxHp * 2, {}))
		world:advance(Creatures.Defs.HoarfangYeti.emerge + 1)
		local enc = svc.EncounterService.get(seal.id)
		t.eq(enc.def.id, "HoarfangYeti")
		svc.EncounterService.hit(enc, player, 1e13, { skill = "ChargedSmash" })
		t.eq(enc.sm.state, "DEFEATED")
		t.truthy(session.data.coins > coins, "it pays")
		t.eq(Guardians.defeated(session.data, "Crystalfall"), false, "the guardian is still ahead")
		t.eq(session.data.islands.completed.Crystalfall, nil)
		t.eq(session.data.stats.guardianVictories, 0)
		t.eq(notifies(world, player, "GuardianVictory"), 0)
		local first = lastReward(world, player, "CreatureReward")
		t.eq(first.boss, true)
		-- it comes back when the seal re-forms and pays the same again (no repeat penalty, no one-off bonus)
		world:placeCharacter(player, V.new(400, 3, 400))
		world:advance(Creatures.Config.recovery + 5 + Creatures.Config.guardianRespawn + 5)
		t.eq(seal.state.alive, true)
		world:placeCharacter(player, seal.base.Position + V.new(10, 3, 0))
		svc.RockService.damage(seal, player, player.UserId, seal.state.maxHp * 2, {})
		world:advance(Creatures.Defs.HoarfangYeti.emerge + 1)
		svc.EncounterService.hit(svc.EncounterService.get(seal.id), player, 1e13, { skill = "ChargedSmash" })
		t.eq(lastReward(world, player, "CreatureReward").coins, first.coins)
		world:assertNoErrors()
	end)

	t.test("momentum multiplies a mini boss's reward too", function()
		local world, svc, player, session = setup(730)
		session.data.islands.unlocked.Crystalfall = true
		session.data.rebirths = 2
		local function fight(x)
			local seal = svc.RockService.spawnAt("RimeSeal", V.new(x, 0, 40), "Crystalfall")
			world:placeCharacter(player, seal.base.Position + V.new(10, 3, 0))
			svc.RockService.damage(seal, player, player.UserId, seal.state.maxHp * 2, {})
			world:advance(Creatures.Defs.GlaciermawWyrm.emerge + 1)
			svc.EncounterService.hit(svc.EncounterService.get(seal.id), player, 1e13, { skill = "ShatterWave" })
			return lastReward(world, player, "CreatureReward")
		end
		local plain = fight(0)
		Momentum.grant(session, "Crystalfall", 0)
		local boosted = fight(60)
		t.near(boosted.xp, plain.xp * 1.5, 1.01)
		world:assertNoErrors()
	end)
end
