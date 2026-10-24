-- Rock -> creature -> combat -> reward -> respawn, and the guardian gate, on the fake server with the REAL services.
local roblox = require("@lune/roblox")
local ServerWorld = require("./support/ServerWorld")

return function(t, u)
	local Game = u:load("Config/Game")
	local Creatures = u:load("Config/Creatures")
	local Rocks = u:load("Config/Rocks")
	local Sim = u:load("Logic/CreatureSim")
	local Guardians = u:load("Logic/Guardians")
	local V = roblox.Vector3

	local function setup(userId)
		local world = ServerWorld.new()
		local svc = world:boot({ encounters = true })
		local player = world:join(userId or 601)
		local session = svc.Sessions.get(player)
		return world, svc, player, session
	end

	local function rockAt(svc, id, x, z, island)
		return svc.RockService.spawnAt(id, V.new(x, 0, z), island or "Forgeheart")
	end

	local function place(world, player, entry, dist)
		world:placeCharacter(player, entry.base.Position + V.new(dist or 6, 3, 0))
	end

	local function breakRock(svc, entry, player)
		return svc.RockService.damage(entry, player, player.UserId, entry.state.maxHp * 2, {})
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

	local function fx(world, kind)
		local n = 0
		for _, args in world:sent("Fx") do
			if args[1] == kind then
				n += 1
			end
		end
		return n
	end

	-- emerged and fightable
	local function awaken(world, entry)
		world:advance(4.5)
	end

	-- Rock -> creature ----------------------------------------------------------------------------------------------------

	t.test("partial damage never releases the creature", function()
		local world, svc, player = setup()
		local rock = rockAt(svc, "Granite", 0, 40)
		svc.RockService.damage(rock, player, player.UserId, rock.state.maxHp * 0.9, {})
		t.eq(rock.state.alive, true)
		t.eq(svc.EncounterService.get(rock.id), nil)
		t.eq(svc.EncounterService.activeCount(), 0)
		t.eq(world.creatureBuilds[rock.id], nil)
		world:advance(30)
		t.eq(world.creatureBuilds[rock.id], nil)
		world:assertNoErrors()
	end)

	t.test("the final hit releases exactly one creature, which emerges invulnerable and then fights", function()
		local world, svc, player = setup()
		local rock = rockAt(svc, "Granite", 0, 40)
		place(world, player, rock)
		t.truthy(breakRock(svc, rock, player))
		local enc = svc.EncounterService.get(rock.id)
		t.truthy(enc)
		t.eq(enc.sm.state, "REVEAL")
		t.eq(world.creatureBuilds[rock.id], 1)
		t.eq(fx(world, "Reveal"), 1)
		t.eq(enc.model:GetAttribute("RockId"), rock.id)
		t.eq(enc.model:GetAttribute("Name"), "Cairn Crawler")
		-- hurt during the reveal: ignored
		local early = svc.EncounterService.hit(enc, player, 50, {})
		t.eq(early, nil)
		world:advance(Creatures.Defs.CairnCrawler.emerge + 0.3)
		t.eq(enc.sm.state, "COMBAT")
		t.eq(enc.model:GetAttribute("Alive"), true)
		world:assertNoErrors()
	end)

	t.test("duplicate final hits and re-entrant begins cannot spawn a second creature", function()
		local world, svc, player = setup()
		local rock = rockAt(svc, "Granite", 0, 40)
		breakRock(svc, rock, player)
		t.eq(breakRock(svc, rock, player), nil, "the wreck cannot be hit again")
		t.eq(svc.RockService.damage(rock, player, player.UserId, 1e9, {}), nil)
		world:advance(20)
		t.eq(world.creatureBuilds[rock.id], 1)
		t.eq(svc.EncounterService.get(rock.id).sm.spawns, 1)
		world:assertNoErrors()
	end)

	t.test("the rock does not rebuild while its creature is alive", function()
		local world, svc, player = setup()
		local rock = rockAt(svc, "Granite", 0, 40)
		world:placeCharacter(player, V.new(300, 3, 300))
		breakRock(svc, rock, player)
		world:advance(Game.Rocks.aftermath + rock.def.respawn + 30)
		t.eq(rock.state.alive, false, "still a wreck: the creature has not been dealt with")
		t.eq(world.rockBuilds[rock.id], 1)
		world:assertNoErrors()
	end)

	t.test("mining pays its share and the creature pays once through its own path", function()
		local world, svc, player, session = setup()
		local rock = rockAt(svc, "Granite", 0, 40)
		place(world, player, rock)
		local c0 = session.data.coins
		breakRock(svc, rock, player)
		local afterMining = session.data.coins
		local mined = afterMining - c0
		t.eq(mined, math.floor(rock.def.coins * rock.def.miningShare * 1.1), "mining share (with the last-hit bonus)")
		t.eq(notifies(world, player, "Reward"), 1)
		awaken(world, rock)
		local enc = svc.EncounterService.get(rock.id)
		svc.EncounterService.hit(enc, player, 1e9, {})
		local gained = session.data.coins - afterMining
		t.truthy(gained > 0, "the creature paid")
		t.eq(notifies(world, player, "CreatureReward"), 1)
		t.eq(notifies(world, player, "Reward"), 1, "no second mining reward")
		t.eq(session.data.stats.creaturesDefeated, 1)
		-- hitting the corpse or re-reporting the kill pays nothing more
		local before = session.data.coins
		t.eq(svc.EncounterService.hit(enc, player, 1e9, {}), nil)
		world:advance(20)
		t.eq(session.data.coins, before)
		t.eq(notifies(world, player, "CreatureReward"), 1)
		world:assertNoErrors()
	end)

	t.test("a defeated creature stays dead, its corpse is removed and the rock re-seals for a second life", function()
		local world, svc, player = setup()
		local rock = rockAt(svc, "Granite", 0, 40)
		place(world, player, rock)
		breakRock(svc, rock, player)
		awaken(world, rock)
		local enc = svc.EncounterService.get(rock.id)
		local model = enc.model
		svc.EncounterService.hit(enc, player, 1e9, {})
		t.eq(enc.sm.state, "DEFEATED")
		t.eq(svc.EncounterService.targetFor(rock.id), nil, "a defeated creature is not a target")
		world:advance(Creatures.Config.recovery + 0.5)
		t.truthy(world.isDestroyed(model), "corpse removed")
		t.eq(enc.sm.state, "RESPAWNING")
		world:placeCharacter(player, V.new(300, 3, 300))
		world:advance(rock.def.respawn + 1)
		t.eq(rock.state.alive, true)
		t.eq(enc.sm.state, "SEALED")
		t.eq(svc.EncounterService.activeCount(), 0)
		-- second life works and spawns exactly one more creature
		place(world, player, rock)
		breakRock(svc, rock, player)
		t.eq(enc.sm.spawns, 2)
		t.eq(world.creatureBuilds[rock.id], 2)
		world:assertNoErrors()
	end)

	t.test("the rock's own respawn is not triggered until the encounter finishes (no overlap)", function()
		local world, svc, player = setup()
		local rock = rockAt(svc, "Granite", 0, 40)
		place(world, player, rock)
		breakRock(svc, rock, player)
		awaken(world, rock)
		local enc = svc.EncounterService.get(rock.id)
		world:advance(rock.def.respawn + 10) -- long enough for the old timer
		t.eq(rock.state.alive, false)
		t.truthy(enc.model and not world.isDestroyed(enc.model))
		t.eq(world.rockBuilds[rock.id], 1)
	end)

	-- Combat through the real remotes -------------------------------------------------------------------------------

	local function punch(world, player, id)
		world:fire("Punch", player, id, 1)
		world:advance(0.7)
	end

	t.test("punches reduce the creature's health; invalid, distant and spammed requests do not", function()
		local world, svc, player, session = setup()
		local rock = rockAt(svc, "Granite", 0, 40)
		place(world, player, rock, 5)
		breakRock(svc, rock, player)
		awaken(world, rock)
		local enc = svc.EncounterService.get(rock.id)
		-- keep it alive and calm for a clean damage reading
		enc.sim.hp = enc.sim.maxHp
		local hp = enc.sim.hp
		punch(world, player, rock.id)
		t.truthy(enc.sim.hp < hp, "a valid punch landed")
		t.eq(session.combat.combo, 1)
		-- out of reach
		local hp2 = enc.sim.hp
		world:placeCharacter(player, enc.sim.pos + V.new(90, 3, 0))
		punch(world, player, rock.id)
		t.eq(enc.sim.hp >= hp2, true)
		-- nonsense ids
		for _, bad in { -1, 0, 1e12, "x", 0.5 } do
			world:fire("Punch", player, bad, 1)
		end
		world:advance(1)
		world:assertNoErrors()
	end)

	t.test("a player on a locked island cannot hurt its creature", function()
		local world, svc, player, session = setup()
		local rock = rockAt(svc, "Quartz", 840, 40, "Crystalfall")
		place(world, player, rock, 5)
		session.data.islands.unlocked.Crystalfall = true
		breakRock(svc, rock, player)
		awaken(world, rock)
		local enc = svc.EncounterService.get(rock.id)
		session.data.islands.unlocked.Crystalfall = nil
		local hp = enc.sim.hp
		punch(world, player, rock.id)
		t.eq(enc.sim.hp >= hp, true)
	end)

	t.test("creatures telegraph first, then damage players still inside the area; stepping out avoids it", function()
		local world, svc, player = setup()
		local rock = rockAt(svc, "Granite", 0, 40)
		place(world, player, rock, 7)
		breakRock(svc, rock, player)
		world:advance(Creatures.Defs.CairnCrawler.emerge + 0.9)
		local hum = player.Character.Humanoid
		-- step in small increments until the first telegraph appears: the player must still be unharmed at that moment
		local telegraphed = false
		for _ = 1, 80 do
			world:advance(0.05)
			if fx(world, "Telegraph") >= 1 then
				telegraphed = true
				t.eq(hum.Health, 100, "a telegraph is sent before any damage")
				break
			end
		end
		t.truthy(telegraphed)
		world:advance(2)
		t.truthy(hum.Health < 100, "caught in the lunge line")
		-- a fresh player who keeps far away is never touched
		local far = world:join(602)
		world:placeCharacter(far, rock.base.Position + V.new(120, 3, 0))
		world:advance(10)
		t.eq(far.Character.Humanoid.Health, 100)
		world:assertNoErrors()
	end)

	t.test("armor: basic punches are blunted, Charged Smash opens it", function()
		local world, svc, player, session = setup()
		session.data.level = 10
		session.data.skills.ranks.ChargedSmash = 1
		local rock = rockAt(svc, "Ironvein", 0, 40)
		place(world, player, rock, 6)
		breakRock(svc, rock, player)
		awaken(world, rock)
		local enc = svc.EncounterService.get(rock.id)
		t.truthy(enc.def.armor)
		enc.sim.coreOpenUntil = 0 -- (a recovering creature shows its core instead of its armor)
		t.eq(Sim.status(enc.sim, world.sched.now).armored, true)
		world:fire("Skill", player, "ChargedSmash", rock.id)
		world:advance(1.5)
		t.eq(Sim.status(enc.sim, world.sched.now).armorOpen, true, "armor is broken by the skill")
		world:assertNoErrors()
	end)

	t.test("a skill the player has not learned is rejected against creatures too", function()
		local world, svc, player, session = setup()
		local rock = rockAt(svc, "Ironvein", 0, 40)
		place(world, player, rock, 6)
		breakRock(svc, rock, player)
		awaken(world, rock)
		local enc = svc.EncounterService.get(rock.id)
		world:fire("Skill", player, "ChargedSmash", rock.id)
		world:advance(1.5)
		t.eq(Sim.status(enc.sim, world.sched.now).armorOpen, false)
		t.eq(enc.sim.hp, enc.sim.maxHp)
	end)

	t.test("two players landing the final blows in the same moment produce one defeat and one reward each", function()
		local world, svc, a, sa = setup(610)
		local b = world:join(611)
		local sb = svc.Sessions.get(b)
		local rock = rockAt(svc, "Granite", 0, 40)
		place(world, a, rock, 5)
		place(world, b, rock, -5)
		breakRock(svc, rock, a)
		awaken(world, rock)
		local enc = svc.EncounterService.get(rock.id)
		local half = enc.sim.maxHp * 0.5
		svc.EncounterService.hit(enc, a, half, {})
		svc.EncounterService.hit(enc, b, half + 1e6, {}) -- b kills
		local late = svc.EncounterService.hit(enc, a, 1e6, {}) -- a's "simultaneous" final hit
		t.eq(late, nil)
		t.eq(enc.sm.rewards, 1)
		t.eq(notifies(world, a, "CreatureReward"), 1)
		t.eq(notifies(world, b, "CreatureReward"), 1)
		t.eq(sa.data.stats.creaturesDefeated, 1)
		t.eq(sb.data.stats.creaturesDefeated, 1)
		world:assertNoErrors()
	end)

	-- Interruptions and cleanup -------------------------------------------------------------------------------------------

	t.test("when every player leaves, the creature stands down, then retreats and the rock re-seals with no reward", function()
		local world, svc, player, session = setup()
		local rock = rockAt(svc, "Granite", 0, 40)
		place(world, player, rock, 5)
		breakRock(svc, rock, player)
		awaken(world, rock)
		local enc = svc.EncounterService.get(rock.id)
		svc.EncounterService.hit(enc, player, 10, {})
		world:leave(player)
		world:advance(Creatures.Config.idleDespawn + 20)
		t.eq(svc.EncounterService.activeCount(), 0)
		t.eq(enc.sm.state == "RESPAWNING" or enc.sm.state == "SEALED", true)
		world:advance(rock.def.respawn + 10)
		t.eq(rock.state.alive, true, "the rock is usable again")
		t.eq(enc.sm.state, "SEALED")
		world:assertNoErrors()
	end)

	t.test("a player who dies mid-fight is no longer a target and the fight resets safely when nobody remains", function()
		local world, svc, player = setup()
		local rock = rockAt(svc, "Granite", 0, 40)
		place(world, player, rock, 5)
		breakRock(svc, rock, player)
		awaken(world, rock)
		local enc = svc.EncounterService.get(rock.id)
		svc.EncounterService.hit(enc, player, 10, {})
		player.Character.Humanoid.Health = 0
		world:advance(Creatures.Config.idleDespawn + 30)
		t.eq(enc.sm.state == "RESPAWNING" or enc.sm.state == "SEALED", true)
		world:assertNoErrors()
	end)

	-- Guardians -----------------------------------------------------------------------------------------------------------

	local function sealAt(svc)
		return svc.RockService.spawnAt("AnvilSeal", V.new(0, 0, 40), "Forgeheart")
	end

	t.test("the guardian seal resists a player who has not reached the rebirth requirement", function()
		local world, svc, player, session = setup()
		local seal = sealAt(svc)
		place(world, player, seal, 8)
		local hp = seal.state.hp
		local r = svc.RockService.damage(seal, player, player.UserId, 1e6, {})
		t.eq(r, nil)
		t.eq(seal.state.hp, hp)
		-- through the real punch path as well
		world:fire("Punch", player, seal.id, 1)
		world:advance(1)
		t.eq(seal.state.hp, hp)
		t.eq(session.combat.combo, 0, "no stacks from a sealed target")
		local toast = false
		for _, args in world:sent("Notify", player) do
			if args[1] == "Toast" and string.find(args[2].text, "Rebirth 1", 1, true) then
				toast = true
			end
		end
		t.truthy(toast, "the player is told what is missing")
		world:assertNoErrors()
	end)

	local function fightBoss(world, svc, player)
		local seal = sealAt(svc)
		place(world, player, seal, 10)
		t.truthy(breakRock(svc, seal, player))
		world:advance(Creatures.Defs.GromAnvilKing.emerge + 1)
		local enc = svc.EncounterService.get(seal.id)
		t.eq(enc.def.tier, "boss")
		return seal, enc
	end

	t.test("an eligible player breaks the seal, defeats the guardian and the completion is recorded for them alone", function()
		local world, svc, player, session = setup(620)
		local bystander = world:join(621)
		local sb = svc.Sessions.get(bystander)
		session.data.rebirths = 1
		sb.data.rebirths = 1
		local seal, enc = fightBoss(world, svc, player)
		world:placeCharacter(bystander, seal.base.Position + V.new(-12, 3, 0))
		svc.EncounterService.hit(enc, player, 1e12, { skill = "ChargedSmash" })
		t.eq(enc.sm.state, "DEFEATED")
		t.eq(Guardians.defeated(session.data, "Forgeheart"), true)
		t.eq(session.data.islands.completed.Forgeheart, true)
		t.eq(session.data.stats.guardianVictories, 1)
		t.eq(Guardians.defeated(sb.data, "Forgeheart"), false, "a bystander gets nothing")
		t.eq(sb.data.islands.completed.Forgeheart, nil)
		t.eq(notifies(world, player, "GuardianVictory"), 1)
		t.eq(notifies(world, bystander, "GuardianVictory"), 0)
		world:assertNoErrors()
	end)

	t.test("an ineligible player near an active guardian can neither hurt it nor be rewarded or hurt by it", function()
		local world, svc, hero, sh = setup(630)
		local weak = world:join(631)
		local sw = svc.Sessions.get(weak)
		sh.data.rebirths = 1
		local seal, enc = fightBoss(world, svc, hero)
		world:placeCharacter(weak, seal.base.Position + V.new(-8, 3, 0))
		local hp = enc.sim.hp
		t.eq(svc.EncounterService.hit(enc, weak, 1e6, {}), nil)
		world:fire("Punch", weak, seal.id, 1)
		world:advance(1)
		t.eq(enc.sim.hp, hp)
		world:advance(15)
		t.eq(weak.Character.Humanoid.Health, 100, "the guardian only fights those who can face it")
		svc.EncounterService.hit(enc, hero, 1e12, {})
		t.eq(Guardians.defeated(sw.data, "Forgeheart"), false)
		t.eq(notifies(world, weak, "CreatureReward"), 0)
	end)

	t.test("beating the guardian again is a smaller reward and not a second completion", function()
		local world, svc, player, session = setup(640)
		session.data.rebirths = 1
		local seal, enc = fightBoss(world, svc, player)
		local c0 = session.data.coins
		svc.EncounterService.hit(enc, player, 1e12, {})
		local first = session.data.coins - c0
		t.truthy(first > 0)
		world:placeCharacter(player, V.new(400, 3, 400))
		world:advance(Creatures.Config.recovery + 5 + Creatures.Config.guardianRespawn + 5)
		t.eq(seal.state.alive, true)
		local seal2, enc2 = seal, svc.EncounterService.get(seal.id)
		place(world, player, seal2, 10)
		breakRock(svc, seal2, player)
		world:advance(Creatures.Defs.GromAnvilKing.emerge + 1)
		local c1 = session.data.coins
		svc.EncounterService.hit(enc2, player, 1e12, {})
		local repeatGain = session.data.coins - c1
		t.truthy(repeatGain < first * 0.5, `repeat {repeatGain} vs first {first}`)
		t.eq(session.data.stats.guardianVictories, 1)
		t.eq(notifies(world, player, "GuardianVictory"), 1, "the completion event fires once")
		world:assertNoErrors()
	end)

	t.test("the next island opens only with the victory AND the rebirths, end to end through the real requests", function()
		local world, svc, player, session = setup(650)
		world:addTagged("Skyport", V.new(10, 0, 10))
		world:placeCharacter(player, V.new(0, 3, 0))
		session.data.level = 5
		session.data.coins = 1e7
		-- rebirth requirement met but guardian undefeated
		session.data.rebirths = 1
		t.eq(world:invoke(player, "UnlockIsland", { islandId = "Mossveil" }).ok, false)
		-- victory recorded
		local seal, enc = fightBoss(world, svc, player)
		svc.EncounterService.hit(enc, player, 1e12, {})
		world:placeCharacter(player, V.new(0, 3, 0))
		t.eq(world:invoke(player, "UnlockIsland", { islandId = "Mossveil" }).ok, true)
		t.eq(world:invoke(player, "UnlockIsland", { islandId = "Crystalfall" }).ok, false, "one guardian opens one island")
		world:assertNoErrors()
	end)

	t.test("clients cannot fake a guardian victory or an island completion", function()
		local world, svc, player, session = setup()
		for _, action in { "DefeatGuardian", "GuardianDefeated", "CompleteIsland", "SetGuardian", "Rebirth2" } do
			t.eq(world:invoke(player, action, { islandId = "Forgeheart" }).err, "unknown_action", action)
		end
		t.eq(world:invoke(player, "SetSetting", { key = "guardians", value = true }).ok, false)
		t.eq(world:invoke(player, "SetSetting", { key = "islands", value = {} }).ok, false)
		t.eq(Guardians.defeated(session.data, "Forgeheart"), false)
		-- and no Net remote accepts creature damage or rewards
		local Net = world:shared("Net")
		for _, name in Net.Events do
			t.truthy(not string.find(string.lower(name), "creature", 1, true), name)
		end
	end)

	t.test("guardian victory persists across leave and rejoin and is never shared with other accounts", function()
		local world, svc, player, session = setup(660)
		session.data.rebirths = 1
		local seal, enc = fightBoss(world, svc, player)
		svc.EncounterService.hit(enc, player, 1e12, {})
		world:leave(player)
		local again = world:join(660)
		local back = svc.Sessions.get(again).data
		t.eq(Guardians.defeated(back, "Forgeheart"), true)
		t.eq(back.islands.completed.Forgeheart, true)
		local other = world:join(661)
		t.eq(Guardians.defeated(svc.Sessions.get(other).data, "Forgeheart"), false)
		world:assertNoErrors()
	end)

	t.test("a boss fight interrupted by the player leaving changes no permanent progress and the guardian recovers", function()
		local world, svc, player, session = setup(670)
		session.data.rebirths = 1
		local seal, enc = fightBoss(world, svc, player)
		svc.EncounterService.hit(enc, player, enc.sim.maxHp * 0.3, {})
		world:leave(player)
		local again = world:join(670)
		local data = svc.Sessions.get(again).data
		t.eq(Guardians.defeated(data, "Forgeheart"), false)
		t.eq(data.stats.guardianVictories, 0)
		world:placeCharacter(again, V.new(400, 3, 400))
		world:advance(Creatures.Config.idleDespawn + 60)
		t.eq(seal.state.alive, true, "the seal re-forms; the encounter is not stuck")
		t.eq(svc.EncounterService.activeCount(), 0)
		world:assertNoErrors()
	end)

	t.test("creature health follows the declared reference fight (arm dps x seconds)", function()
		local Stats = u:load("Logic/CreatureStats")
		for id, c in Creatures.Defs do
			local hp = Stats.maxHp(c)
			t.truthy(hp >= 100, id .. " has real health")
			t.near(hp, Stats.referenceDps(c.fight.arm, c.fight.level) * c.fight.seconds, 1, id)
		end
		-- and a creature's fight is at least as long as the tier above it is demanding
		local small = Stats.maxHp(Creatures.Defs.CairnCrawler) / Stats.referenceDps("Starter", 0)
		local boss = Stats.maxHp(Creatures.Defs.GromAnvilKing) / Stats.referenceDps("Alloy", 2)
		t.truthy(boss > small * 5)
	end)
end
