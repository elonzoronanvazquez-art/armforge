-- Dock fishing, The Atlantic Sea, the swing vines and The Canopy Grove: the pure rules, the zone config and the server glue on the fake server.
local roblox = require("@lune/roblox")
local ServerWorld = require("./support/ServerWorld")

return function(t, u)
	local Fishing = u:load("Logic/Fishing")
	local FishingCfg = u:load("Config/Fishing")
	local Zones = u:load("Config/Zones")
	local Islands = u:load("Logic/Islands")
	local IslandCfg = u:load("Config/Islands")
	local Rocks = u:load("Config/Rocks")
	local Creatures = u:load("Config/Creatures")
	local Rng = u:load("Util/Rng")
	local V = roblox.Vector3

	-- Pure rules ----------------------------------------------------------------------------------------------------------------

	t.test("a cast waits between the configured bounds for a bite, then offers a reel window", function()
		local cfg = FishingCfg.Config
		for seed = 1, 200 do
			local cast = Fishing.cast(100, Rng.new(seed))
			local wait = cast.biteAt - 100
			t.truthy(wait >= cfg.biteMin and wait <= cfg.biteMax, `wait {wait}`)
			t.near(cast.expiresAt - cast.biteAt, cfg.reelWindow, 1e-9)
		end
	end)

	t.test("reeling early, in the window and late", function()
		local cast = { castAt = 0, biteAt = 4, expiresAt = 6.2 }
		t.eq(Fishing.reel(cast, 1), "early")
		t.eq(Fishing.reel(cast, 3.99), "early")
		t.eq(Fishing.reel(cast, 4), "caught")
		t.eq(Fishing.reel(cast, 6.2), "caught")
		t.eq(Fishing.reel(cast, 6.21), "missed")
	end)

	t.test("catches follow the weights, rewards scale with level, and one catch in ten sails to the Atlantic", function()
		local rng = Rng.new(2024)
		local counts, sails, n = {}, 0, 40000
		local total = 0
		for _, f in FishingCfg.Fish do
			total += f.weight
		end
		for _ = 1, n do
			local c = Fishing.roll(rng, 1)
			counts[c.fish.id] = (counts[c.fish.id] or 0) + 1
			if c.sail then
				sails += 1
			end
		end
		t.near(sails / n, FishingCfg.Config.sailChance, 0.01, "10% sail chance")
		for _, f in FishingCfg.Fish do
			t.near((counts[f.id] or 0) / n, f.weight / total, 0.01, f.id)
		end
		local low, high = Fishing.roll(Rng.new(5), 1), Fishing.roll(Rng.new(5), 31)
		t.eq(low.fish.id, high.fish.id, "same seed, same fish")
		t.truthy(high.coins > low.coins and high.xp > low.xp, "higher levels earn more")
		t.near(Fishing.levelScale(1), 1, 1e-9)
	end)

	t.test("a vine swing flings about 2% of the time", function()
		local rng = Rng.new(99)
		local hits, n = 0, 50000
		for _ = 1, n do
			if Fishing.vineFlings(rng) then
				hits += 1
			end
		end
		t.near(hits / n, 0.02, 0.005)
		t.near(FishingCfg.Vines.teleportChance, 0.02, 1e-9)
	end)

	-- Zones -------------------------------------------------------------------------------------------------------------------------

	t.test("The Atlantic Sea pays 25% more coins and XP and is not a rung of the ladder", function()
		local sea = Zones.Defs.AtlanticSea
		t.near(sea.boost.coins, 1.25, 1e-9)
		t.near(sea.boost.xp, 1.25, 1e-9)
		t.near(Islands.rewardBoost("AtlanticSea").xp, 1.25, 1e-9)
		t.eq(Islands.boostText("AtlanticSea"), "+25% coins & XP")
		t.eq(IslandCfg.Defs.AtlanticSea, nil)
		t.eq(table.find(IslandCfg.Order, "AtlanticSea"), nil)
		t.eq(Islands.rewardBoost("CanopyGrove").coins, 1, "the grove has no boost")
	end)

	t.test("zones are open to whoever gets there; the ladder still needs an unlock", function()
		local d = u:load("Logic/DataSchema").default()
		t.eq(Islands.open(d, "AtlanticSea"), true)
		t.eq(Islands.open(d, "CanopyGrove"), true)
		t.eq(Islands.open(d, "Forgeheart"), true)
		t.eq(Islands.open(d, "Dustwake"), false)
		t.eq(Islands.open(d, "Nowhere"), false)
	end)

	t.test("every zone rock and creature exists, belongs to the zone and is placed inside it", function()
		for _, zoneId in Zones.Order do
			local zone = Zones.Defs[zoneId]
			t.truthy(zone.arrival.Y >= zone.center.Y, zoneId .. " arrival is above the ground")
			for _, field in zone.fields do
				local flat = (V.new(field.center.X, 0, field.center.Z) - V.new(zone.center.X, 0, zone.center.Z)).Magnitude
				t.truthy(flat + field.radius < zone.radius * 0.8, field.name .. " sits on land")
				for _, entry in field.rocks do
					local rock = Rocks.Defs[entry.rock]
					t.eq(rock.island, zoneId, entry.rock)
					t.truthy(Creatures.Defs[rock.encounter], entry.rock .. " holds a creature")
					t.eq(Creatures.Defs[rock.encounter].island, zoneId)
				end
			end
		end
		t.truthy(Zones.Defs.CanopyGrove.gift and Zones.Defs.CanopyGrove.gift.cooldown > 0)
		t.truthy(Rocks.Defs[Zones.Defs.CanopyGrove.gift.rock], "the gift is measured against a real rock")
	end)

	-- Server glue ---------------------------------------------------------------------------------------------------------------

	local function setup(userId)
		local world = ServerWorld.new({ studio = true })
		local svc = world:boot({ encounters = true })
		local spot = world:addTagged("FishingSpot", V.new(0, 3, 150))
		local Fish = world:load("Services/FishingService")
		Fish.start()
		local player = world:join(userId or 901)
		world:placeCharacter(player, V.new(0, 3, 148))
		return world, svc, Fish, player, svc.Sessions.get(player)
	end

	local function stub(nextValue, rangeValue)
		return {
			next = function()
				return nextValue
			end,
			range = function(_, lo)
				return rangeValue or lo
			end,
		}
	end

	local function phases(world, player)
		local out = {}
		for _, args in world:sent("Notify", player) do
			if args[1] == "Fishing" then
				table.insert(out, args[2].phase)
			end
		end
		return out
	end

	t.test("cast, wait, reel in time: a catch that pays, with no sailing at normal luck", function()
		local world, svc, Fish, player, session = setup()
		Fish.setRng(stub(0.5)) -- a Mackerel-ish roll, and 0.5 > 10% so no sail
		t.eq(Fish.trigger(player, world.sched.now), "cast")
		t.truthy(Fish.casting(player))
		local coins, xp = session.data.coins, session.data.xp
		world:advance(FishingCfg.Config.biteMin + 0.1)
		t.deepEq(phases(world, player), { "cast", "bite" })
		t.eq(Fish.trigger(player, world.sched.now), "caught")
		t.truthy(session.data.coins > coins and (session.data.xp > xp or session.data.level > 1))
		t.eq(session.zone, nil)
		t.deepEq(phases(world, player), { "cast", "bite", "catch" })
		world:advance(3)
		t.eq(session.zone, nil, "nothing pulls you out")
		world:assertNoErrors()
	end)

	t.test("a lucky catch (1 in 10) pulls the angler out to The Atlantic Sea, and the sea pays 25% more", function()
		local world, svc, Fish, player, session = setup()
		Fish.setRng(stub(0.01)) -- the first fish in the table, and under 10%: sail
		Fish.trigger(player, world.sched.now)
		world:advance(FishingCfg.Config.biteMin + 0.1)
		t.eq(Fish.trigger(player, world.sched.now), "sail")
		world:advance(2)
		t.eq(session.zone, "AtlanticSea")
		local pos = player.Character.HumanoidRootPart.CFrame.Position
		local arrival = Zones.Defs.AtlanticSea.arrival
		t.truthy((V.new(pos.X, 0, pos.Z) - V.new(arrival.X, 0, arrival.Z)).Magnitude < 20, "stands at the atoll")
		t.eq(session.data.islands.current, "Forgeheart", "the ladder state is untouched")
		-- earning there: the same rock pays 25% more than on the starter island
		local function kill(island, x)
			world:placeCharacter(player, V.new(x, 3, 30))
			local rock = svc.RockService.spawnAt("Brinerock", V.new(x, 0, 40), island)
			svc.RockService.damage(rock, player, player.UserId, rock.state.maxHp * 2, {})
			local reward
			for _, args in world:sent("Notify", player) do
				if args[1] == "Reward" then
					reward = args[2]
				end
			end
			return reward
		end
		local base = kill("Forgeheart", 200)
		local boosted = kill("AtlanticSea", 260)
		t.near(boosted.xp, base.xp * 1.25, 1.01)
		t.near(boosted.coins, base.coins * 1.25, 1.01)
		world:assertNoErrors()
	end)

	t.test("reeling too early spooks the fish, too late loses it, and the line cools down", function()
		local world, svc, Fish, player, session = setup()
		Fish.setRng(stub(0.5))
		local coins = session.data.coins
		Fish.trigger(player, world.sched.now)
		world:advance(0.5)
		t.eq(Fish.trigger(player, world.sched.now), "early")
		t.eq(session.data.coins, coins)
		t.eq(Fish.trigger(player, world.sched.now), "cooldown", "no instant recast")
		world:advance(FishingCfg.Config.cooldown + 0.1)
		t.eq(Fish.trigger(player, world.sched.now), "cast")
		world:advance(FishingCfg.Config.biteMax + FishingCfg.Config.reelWindow + 1)
		t.eq(Fish.casting(player), false, "an unreeled bite is lost")
		local seen = phases(world, player)
		t.eq(seen[#seen], "missed")
		t.eq(session.data.coins, coins)
		world:assertNoErrors()
	end)

	t.test("you cannot fish from far away from the dock", function()
		local world, svc, Fish, player = setup()
		world:placeCharacter(player, V.new(300, 3, 300))
		t.eq(Fish.trigger(player, world.sched.now), "too_far")
		t.eq(Fish.casting(player), false)
		world:assertNoErrors()
	end)

	local function vineSetup()
		local world, svc, _, player, session = setup(910)
		local vineNode = world:addTagged("SwingVine", V.new(40, 3, 40))
		local Vine = world:load("Services/VineService")
		world:placeCharacter(player, V.new(40, 3, 38))
		return world, svc, Vine, player, session, vineNode
	end

	t.test("a vine swing usually does nothing, sometimes flings you to the Canopy Grove, and is rate limited", function()
		local world, svc, Vine, player, session, vine = vineSetup()
		Vine.setRng(stub(0.5))
		t.eq(Vine.swing(player, vine, 100), "swung")
		t.eq(Vine.swing(player, vine, 100.5), "cooldown")
		t.eq(session.zone, nil)
		Vine.setRng(stub(0.001))
		t.eq(Vine.swing(player, vine, 110), "flung")
		world:advance(1)
		t.eq(session.zone, "CanopyGrove")
		local pos = player.Character.HumanoidRootPart.CFrame.Position
		t.truthy(pos.Y > 100, "up in the sky")
		world:assertNoErrors()
	end)

	t.test("a vine out of reach cannot be swung", function()
		local world, svc, Vine, player, session, vine = vineSetup()
		world:placeCharacter(player, V.new(300, 3, 300))
		t.eq(Vine.swing(player, vine, 100), "too_far")
		world:assertNoErrors()
	end)

	t.test("the grove's gift is only for those inside it, pays once per cooldown and then comes back", function()
		local world, svc, Vine, player, session, vine = vineSetup()
		t.eq(Vine.gift(player, 0), "not_in_grove")
		world:invoke(player, "Dev", { line = "goto CanopyGrove" })
		t.eq(session.zone, "CanopyGrove")
		local coins = session.data.coins
		t.eq(Vine.gift(player, 1000), "ok")
		t.truthy(session.data.coins > coins)
		local after = session.data.coins
		t.eq(Vine.gift(player, 1100), "cooldown")
		t.eq(session.data.coins, after)
		t.eq(Vine.gift(player, 1000 + Zones.Defs.CanopyGrove.gift.cooldown + 1), "ok")
		t.truthy(session.data.coins > after)
		world:assertNoErrors()
	end)

	t.test("zones: dev goto and home move you in and out, and the marks never touch the ladder", function()
		local world, svc, Fish, player, session = setup(920)
		t.truthy(world:invoke(player, "Dev", { line = "goto atlanticsea" }).ok)
		t.eq(session.zone, "AtlanticSea")
		t.eq(session.data.islands.current, "Forgeheart")
		t.eq(session.data.islands.unlocked.AtlanticSea, nil)
		t.truthy(world:invoke(player, "Dev", { line = "home" }).ok)
		t.eq(session.zone, nil)
		-- the grove sends you back to the jungle, even if you were last on another island (it was opened by a vine, so the jungle is yours)
		session.data.islands.unlocked.Mossveil = true
		world:invoke(player, "Dev", { line = "goto CanopyGrove" })
		world:invoke(player, "Dev", { line = "home" })
		local pos = player.Character.HumanoidRootPart.CFrame.Position
		local jungle = IslandCfg.Defs.Mossveil.arrival
		t.truthy((V.new(pos.X, 0, pos.Z) - V.new(jungle.X, 0, jungle.Z)).Magnitude < 30)
		world:assertNoErrors()
	end)

	t.test("inside() knows when a player has fallen off the grove or swum away from the atoll", function()
		local ZoneService = world and nil
		local world = ServerWorld.new({ studio = true })
		world:boot({ encounters = true })
		local Zone = world:load("Services/ZoneService")
		local sea, grove = Zones.Defs.AtlanticSea, Zones.Defs.CanopyGrove
		t.truthy(Zone.inside("AtlanticSea", V.new(sea.center.X + 40, 2, sea.center.Z)))
		t.eq(Zone.inside("AtlanticSea", V.new(sea.center.X + 400, 2, sea.center.Z)), false)
		t.truthy(Zone.inside("CanopyGrove", V.new(grove.center.X + 10, grove.center.Y + 4, grove.center.Z)))
		t.eq(Zone.inside("CanopyGrove", V.new(grove.center.X + 10, 5, grove.center.Z)), false, "on the ground below is not the grove")
		t.eq(Zone.inside("Nowhere", V.new(0, 0, 0)), false)
	end)
end
