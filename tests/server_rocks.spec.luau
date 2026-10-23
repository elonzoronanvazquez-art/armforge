-- RockService glue on the fake server: lifecycle, rewards, safe respawn, cleanup and concurrent contributors.
local roblox = require("@lune/roblox")
local ServerWorld = require("./support/ServerWorld")

return function(t, u)
	local Game = u:load("Config/Game")
	local V = roblox.Vector3

	local function setup(rockId)
		local world = ServerWorld.new()
		local svc = world:boot()
		local entry = svc.RockService.spawnAt(rockId or "Granite", V.new(0, 0, 40), "Forgeheart")
		return world, svc, entry
	end

	local function join(world, svc, userId, pos)
		local player = world:join(userId)
		svc.Sessions.get(player).data.islands.unlocked.Forgeheart = true
		world:placeCharacter(player, pos)
		return player, svc.Sessions.get(player)
	end

	local function kill(svc, entry, player)
		return svc.RockService.damage(entry, player, player.UserId, entry.state.maxHp * 2, {})
	end

	local function respawnWindow(entry)
		return Game.Rocks.aftermath + entry.def.respawn
	end

	local function rewards(world, player)
		local n = 0
		for _, args in world:sent("Notify", player) do
			if args[1] == "Reward" then
				n += 1
			end
		end
		return n
	end

	-- Lifecycle ----------------------------------------------------------------------------------------------

	t.test("destroying a rock pays its killer exactly once and leaves rubble", function()
		local world, svc, entry = setup()
		local player, session = join(world, svc, 301, V.new(0, 3, 30))
		local coins = session.data.coins
		t.truthy(kill(svc, entry, player))
		t.eq(entry.state.alive, false)
		t.eq(entry.state.stage, "COLLAPSE")
		t.truthy(entry.rubble, "rubble placed")
		t.lt(coins, session.data.coins, "coins granted")
		t.eq(session.data.stats.rocksDestroyed, 1)
		t.eq(rewards(world, player), 1)
		-- hitting the wreck again changes nothing and pays nothing more
		t.eq(svc.RockService.damage(entry, player, player.UserId, 1000, {}), nil)
		local after = session.data.coins
		world:advance(0.5)
		t.eq(session.data.coins, after)
		t.eq(rewards(world, player), 1)
		world:assertNoErrors()
	end)

	t.test("a rock respawns after its timer with full health, a new generation and no leftover rubble", function()
		local world, svc, entry = setup()
		local player = join(world, svc, 302, V.new(200, 3, 200))
		local generation = entry.state.generation
		kill(svc, entry, player)
		local rubble = entry.rubble
		world:advance(respawnWindow(entry) + 0.5)
		t.truthy(entry.state.alive)
		t.eq(entry.state.hp, entry.state.maxHp)
		t.eq(entry.state.generation, generation + 1)
		t.eq(entry.rubble, nil)
		t.truthy(world.isDestroyed(rubble), "old rubble destroyed")
		t.eq(world.rockBuilds[entry.id], 2, "rebuilt exactly once")
		world:assertNoErrors()
	end)

	t.test("rewards go to every contributor still in the server and skip players who left", function()
		local world, svc, entry = setup("Ironvein")
		local a, sa = join(world, svc, 303, V.new(0, 3, 30))
		local b, sb = join(world, svc, 304, V.new(3, 3, 30))
		local c, sc = join(world, svc, 305, V.new(-3, 3, 30))
		local half = entry.state.maxHp * 0.3
		svc.RockService.damage(entry, a, a.UserId, half, {})
		svc.RockService.damage(entry, b, b.UserId, half, {})
		svc.RockService.damage(entry, c, c.UserId, half, {})
		local coinsB = sb.data.coins
		world:leave(b)
		svc.RockService.damage(entry, a, a.UserId, entry.state.maxHp, {}) -- a lands the killing blow
		t.eq(rewards(world, a), 1)
		t.eq(rewards(world, c), 1)
		t.eq(rewards(world, b), 0, "a player who left gets no reward and nothing errors")
		t.eq(sb.data.coins, coinsB)
		world:assertNoErrors()
	end)

	t.test("a contributor without a loaded session is skipped safely", function()
		local world, svc, entry = setup()
		local player, session = join(world, svc, 306, V.new(0, 3, 30))
		session.loaded = false
		kill(svc, entry, player)
		t.eq(session.data.stats.rocksDestroyed, 0)
		world:assertNoErrors()
	end)

	t.test("hitting a rock stage by stage updates its attributes and removes chunks", function()
		local world, svc, entry = setup("Ironvein")
		local player = join(world, svc, 307, V.new(0, 3, 30))
		local stages = { [entry.state.stage] = true }
		for _ = 1, 60 do
			if not entry.state.alive then
				break
			end
			svc.RockService.damage(entry, player, player.UserId, entry.state.maxHp * 0.04, { hitDir = V.new(1, 0, 0) })
			stages[entry.state.stage] = true
		end
		t.truthy(stages.SURFACE or stages.CHIPPED or stages.FRACTURED, "progressed through damage stages")
		t.truthy(entry.state.removedCount > 0 or not entry.state.alive)
		world:assertNoErrors()
	end)

	-- Safe respawn -------------------------------------------------------------------------------------------

	local function stand(entry)
		return entry.base.Position + V.new(1, 3, 1)
	end

	t.test("a player standing in the footprint holds the respawn: not moved, not hurt, no model built", function()
		local world, svc, entry = setup()
		local player = join(world, svc, 310, V.new(200, 3, 200))
		kill(svc, entry, player)
		world:placeCharacter(player, stand(entry))
		local before = player.Character.HumanoidRootPart.Position
		local health = player.Character.Humanoid.Health
		world:advance(respawnWindow(entry) + 5)
		t.eq(entry.state.alive, false, "still waiting")
		t.eq(world.rockBuilds[entry.id], 1, "nothing built on top of the player")
		t.eq(player.Character.HumanoidRootPart.Position, before, "player not teleported or shoved")
		t.eq(player.Character.Humanoid.Health, health, "player not damaged")
		world:assertNoErrors()
	end)

	t.test("the rock comes back as soon as the footprint is clear", function()
		local world, svc, entry = setup()
		local player = join(world, svc, 311, V.new(200, 3, 200))
		kill(svc, entry, player)
		world:placeCharacter(player, stand(entry))
		world:advance(respawnWindow(entry) + 5)
		t.eq(entry.state.alive, false)
		world:placeCharacter(player, V.new(200, 3, 200))
		world:advance(Game.Rocks.respawnRetry + 0.1)
		t.truthy(entry.state.alive)
		t.eq(entry.collider.CanCollide, true, "solid")
		t.eq(world.rockBuilds[entry.id], 2)
		world:assertNoErrors()
	end)

	t.test("a player who leaves the server no longer blocks the respawn", function()
		local world, svc, entry = setup()
		local player = join(world, svc, 312, V.new(200, 3, 200))
		kill(svc, entry, player)
		world:placeCharacter(player, stand(entry))
		world:advance(respawnWindow(entry) + 2)
		t.eq(entry.state.alive, false)
		world:leave(player)
		world:advance(Game.Rocks.respawnRetry + 0.1)
		t.truthy(entry.state.alive)
		world:assertNoErrors()
	end)

	t.test("any one of several players is enough to hold the respawn", function()
		local world, svc, entry = setup()
		local a = join(world, svc, 313, V.new(200, 3, 200))
		local b = join(world, svc, 314, V.new(-200, 3, 200))
		kill(svc, entry, a)
		world:placeCharacter(b, stand(entry))
		world:advance(respawnWindow(entry) + 3)
		t.eq(entry.state.alive, false)
		world:placeCharacter(b, V.new(-200, 3, 200))
		world:advance(Game.Rocks.respawnRetry + 0.1)
		t.truthy(entry.state.alive)
	end)

	t.test("a player dead or without a character does not block", function()
		local world, svc, entry = setup()
		local a = join(world, svc, 315, V.new(200, 3, 200))
		local b = join(world, svc, 316, stand(entry))
		kill(svc, entry, a)
		b.Character.HumanoidRootPart.Parent = nil -- character mid-respawn: no root part
		world:advance(respawnWindow(entry) + 1)
		t.truthy(entry.state.alive)
		world:assertNoErrors()
	end)

	t.test("an obstruction that never clears returns the rock non-solid, then solid once the player moves", function()
		local world, svc, entry = setup()
		local player = join(world, svc, 317, V.new(200, 3, 200))
		kill(svc, entry, player)
		world:placeCharacter(player, stand(entry))
		world:advance(respawnWindow(entry) + Game.Rocks.respawnMaxDefer + 2)
		t.truthy(entry.state.alive, "the rock is back so nobody can stall it forever")
		t.eq(entry.collider.CanCollide, false, "ghost: it cannot shove the player standing in it")
		t.eq(entry.model:GetAttribute("Ghost"), true)
		world:advance(10)
		t.eq(entry.collider.CanCollide, false, "still ghost while occupied")
		world:placeCharacter(player, V.new(200, 3, 200))
		world:advance(Game.Rocks.respawnRetry + 0.1)
		t.eq(entry.collider.CanCollide, true, "solid once clear")
		t.eq(entry.model:GetAttribute("Ghost"), nil)
		world:assertNoErrors()
	end)

	t.test("a ghost rock can be mined and destroyed; nothing from it revives later", function()
		local world, svc, entry = setup()
		local player = join(world, svc, 318, V.new(200, 3, 200))
		kill(svc, entry, player)
		world:placeCharacter(player, stand(entry))
		world:advance(respawnWindow(entry) + Game.Rocks.respawnMaxDefer + 2)
		local ghost = entry.collider
		kill(svc, entry, player) -- destroyed while still a ghost
		world:placeCharacter(player, V.new(200, 3, 200))
		world:advance(Game.Rocks.respawnRetry * 3)
		t.eq(entry.state.alive, false, "the old ghost watcher did not resurrect or solidify anything")
		t.eq(ghost.CanCollide, false)
		world:advance(respawnWindow(entry) + 1)
		t.truthy(entry.state.alive)
		t.eq(entry.collider.CanCollide, true)
		world:assertNoErrors()
	end)

	t.test("exactly one respawn happens per death however long it was held back", function()
		local world, svc, entry = setup()
		local player = join(world, svc, 319, V.new(200, 3, 200))
		kill(svc, entry, player)
		world:placeCharacter(player, stand(entry))
		world:advance(respawnWindow(entry) + 8)
		world:placeCharacter(player, V.new(200, 3, 200))
		world:advance(60)
		t.eq(world.rockBuilds[entry.id], 2)
		t.eq(entry.state.generation, 2)
	end)

	-- Spatial queries ------------------------------------------------------------------------------------------

	t.test("near() returns alive rocks within range, nearest first, honouring the exclusion", function()
		local world, svc = setup()
		local R = svc.RockService
		local a = R.spawnAt("Granite", V.new(100, 0, 100), "Forgeheart")
		local b = R.spawnAt("Granite", V.new(108, 0, 100), "Forgeheart")
		local c = R.spawnAt("Granite", V.new(300, 0, 100), "Forgeheart")
		local list = R.near(V.new(101, 0, 100), 20)
		t.eq(#list, 2)
		t.eq(list[1], a)
		t.eq(list[2], b)
		t.eq(#R.near(V.new(101, 0, 100), 20, a.id), 1)
		t.eq(#R.near(V.new(300, 0, 100), 5), 1)
		svc.RockService.damage(b, nil, 999, b.state.maxHp * 2, {})
		t.eq(#R.near(V.new(101, 0, 100), 20), 1, "dead rocks are not returned")
		t.truthy(c)
	end)

	t.test("fxNear reaches only players inside the radius and skips players without a character", function()
		local world, svc = setup()
		local near = join(world, svc, 320, V.new(10, 3, 10))
		local far = join(world, svc, 321, V.new(800, 3, 800))
		local nobody = world:join(322)
		nobody.Character.HumanoidRootPart.Parent = nil
		world:clearSent()
		svc.RockService.fxNear(V.new(0, 0, 0), "Test", { a = 1 }, 50)
		t.eq(#world:sent("Fx", near), 1)
		t.eq(#world:sent("Fx", far), 0)
		t.eq(#world:sent("Fx", nobody), 0)
		world:assertNoErrors()
	end)

	t.test("near() agrees with a brute-force scan over 150 rocks for random queries", function()
		local world, svc = setup()
		local R = svc.RockService
		local rng = u:load("Util/Rng").new(77)
		for i = 1, 150 do
			R.spawnAt(if i % 3 == 0 then "Ironvein" else "Granite", V.new(rng:range(-600, 600), 0, rng:range(-600, 600)), "Forgeheart")
		end
		for id, entry in R.all() do
			if id % 7 == 0 then
				svc.RockService.damage(entry, nil, 1, entry.state.maxHp * 2, {})
			end
		end
		for _ = 1, 200 do
			local pos = V.new(rng:range(-700, 700), rng:range(0, 10), rng:range(-700, 700))
			local radius = rng:range(1, 120)
			local expected = {}
			for id, e in R.all() do
				if e.state.alive and (e.center - pos).Magnitude <= radius + e.state.layout.radius then
					table.insert(expected, id)
				end
			end
			table.sort(expected)
			local got = {}
			local lastD = -1
			for _, e in R.near(pos, radius) do
				table.insert(got, e.id)
				local d = (e.center - pos).Magnitude
				t.truthy(d >= lastD, "nearest first")
				lastD = d
			end
			table.sort(got)
			t.deepEq(got, expected)
		end
	end)

	-- Burning -------------------------------------------------------------------------------------------------

	t.test("ignite damages a rock once per second for its duration, then stops", function()
		local world, svc, entry = setup("Ironvein")
		local player = join(world, svc, 330, V.new(0, 3, 30))
		local hp = entry.state.hp
		svc.RockService.ignite(entry, player.UserId, 5, 3)
		t.eq(entry.model:GetAttribute("Burning"), true)
		world:advance(10)
		local lost = hp - entry.state.hp
		t.truthy(lost >= 5 * 2 and lost <= 5 * 4, `burned for about three ticks, lost {lost}`)
		t.eq(entry.burn, nil)
		t.eq(entry.model:GetAttribute("Burning"), nil)
		local settled = entry.state.hp
		world:advance(10)
		t.eq(entry.state.hp, settled, "no damage after the burn ended")
		world:assertNoErrors()
	end)

	t.test("a burning rock destroyed by someone else stops burning and pays out once", function()
		local world, svc, entry = setup()
		local player, session = join(world, svc, 331, V.new(0, 3, 30))
		svc.RockService.ignite(entry, player.UserId, 1, 30)
		kill(svc, entry, player)
		world:advance(5)
		t.eq(session.data.stats.rocksDestroyed, 1)
		t.eq(rewards(world, player), 1)
		world:advance(respawnWindow(entry) + 1)
		t.truthy(entry.state.alive)
		t.eq(entry.burn, nil, "a reborn rock does not inherit the old fire")
		local hp = entry.state.hp
		world:advance(5)
		t.eq(entry.state.hp, hp)
		world:assertNoErrors()
	end)
end
