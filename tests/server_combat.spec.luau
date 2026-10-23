-- CombatService + RockService + Requests glue on the fake server: swings, combo/Overclock stacks, invalid input.
local ServerWorld = require("./support/ServerWorld")

return function(t, u)
	local Game = u:load("Config/Game")
	local Combat = u:load("Logic/Combat")
	local Vector3 = require("@lune/roblox").Vector3

	-- A booted server with one player standing in reach of a rock.
	local function arena(armId, rockId)
		local world = ServerWorld.new()
		local svc = world:boot()
		local player = world:join(201)
		local session = svc.Sessions.get(player)
		if armId and armId ~= "Starter" then
			session.data.arms.owned[armId] = true
			session.data.arms.levels[armId] = 0
			t.truthy(world:invoke(player, "Equip", { armId = armId }).ok)
		end
		local entry = svc.RockService.spawnAt(rockId or "Granite", Vector3.new(0, 0, 30), "Forgeheart")
		session.data.islands.unlocked.Forgeheart = true
		world:placeCharacter(player, entry.center + Vector3.new(4, 0, 0))
		world:advance(0.2)
		return world, svc, player, session, entry
	end

	local function punch(world, player, rock, session)
		world:fire("Punch", player, rock and rock.id or 0, 1)
		local stats = Combat.stats(session.data, session.combat, world.sched.now)
		world:advance(stats.cooldown + 0.12) -- let the swing land and the cooldown expire
	end

	t.test("a punch at a rock in reach applies damage and builds the combo", function()
		local world, svc, player, session, entry = arena()
		local hp = entry.state.hp
		punch(world, player, entry, session)
		t.lt(entry.state.hp, hp, "damage applied")
		t.eq(session.combat.combo, 1)
		punch(world, player, entry, session)
		t.eq(session.combat.combo, 2)
		t.eq(session.data.stats.strikes, 2)
		world:assertNoErrors()
	end)

	t.test("swings at nothing do not build combo or Overclock stacks", function()
		local world, svc, player, session = arena("Alloy")
		for _ = 1, 6 do
			punch(world, player, nil, session)
		end
		t.eq(session.combat.combo, 0, "combo")
		t.eq(session.combat.overclock, 0, "overclock")
		local stats = Combat.stats(session.data, session.combat, world.sched.now)
		local base = Combat.stats(session.data, Combat.newState("Alloy"), world.sched.now)
		t.near(stats.cooldown, base.cooldown, 1e-9, "no free haste from whiffing")
		t.eq(session.data.stats.strikes, 0)
		world:assertNoErrors()
	end)

	t.test("a swing at a rock that is out of reach is a whiff", function()
		local world, svc, player, session, entry = arena("Alloy")
		world:placeCharacter(player, entry.center + Vector3.new(80, 0, 0))
		for _ = 1, 4 do
			punch(world, player, entry, session)
		end
		t.eq(session.combat.combo, 0)
		t.eq(session.combat.overclock, 0)
		t.eq(entry.state.hp, entry.state.maxHp, "rock untouched")
	end)

	t.test("a swing at a rock on a locked island is a whiff", function()
		local world, svc, player, session, entry = arena("Alloy")
		session.data.islands.unlocked.Forgeheart = nil
		for _ = 1, 3 do
			punch(world, player, entry, session)
		end
		t.eq(session.combat.combo, 0)
		t.eq(entry.state.hp, entry.state.maxHp)
	end)

	t.test("Overclock stacks come only from landed hits", function()
		local world, svc, player, session, entry = arena("Alloy", "Ironvein")
		punch(world, player, entry, session)
		punch(world, player, entry, session)
		t.eq(session.combat.overclock, 2)
		-- a whiff in between neither adds a stack nor wipes the ones already earned (the chain timer is not extended either)
		punch(world, player, nil, session)
		t.eq(session.combat.overclock, 2)
		punch(world, player, entry, session)
		t.eq(session.combat.overclock, 3)
		world:assertNoErrors()
	end)

	t.test("a rock that dies or moves out of reach before contact does not count as a hit", function()
		local world, svc, player, session, entry = arena("Alloy")
		world:fire("Punch", player, entry.id, 1)
		-- before the animation's contact frame the rock is destroyed by someone else
		svc.RockService.damage(entry, nil, 999, entry.state.hp + 1, {})
		world:advance(1)
		t.eq(session.combat.combo, 0)
		t.eq(session.combat.overclock, 0)

		local world2, svc2, player2, session2, entry2 = arena("Alloy")
		world2:fire("Punch", player2, entry2.id, 1)
		world2:placeCharacter(player2, entry2.center + Vector3.new(200, 0, 0)) -- teleported away mid-swing
		world2:advance(1)
		t.eq(session2.combat.combo, 0)
		t.eq(session2.data.stats.strikes, 0)
	end)

	t.test("a combo that goes quiet restarts at one", function()
		local world, svc, player, session, entry = arena("Alloy", "Ironvein")
		punch(world, player, entry, session)
		punch(world, player, entry, session)
		world:advance(Game.Combat.comboWindow + 0.5)
		punch(world, player, entry, session)
		t.eq(session.combat.combo, 1)
		t.eq(session.combat.overclock, 1)
	end)

	t.test("malformed punch arguments are ignored and never raise", function()
		local world, svc, player, session, entry = arena()
		for _, bad in { "x", -1, 1e12, 0.5, 0 / 0, {}, true } do
			world:fire("Punch", player, bad, "also bad")
			world:advance(1)
		end
		world:fire("Punch", player)
		world:advance(1)
		t.eq(session.combat.combo, 0)
		world:assertNoErrors()
	end)

	t.test("punch spam is rate limited: a thousand requests do not produce a thousand strikes", function()
		local world, svc, player, session, entry = arena("Alloy", "Quartz")
		for _ = 1, 1000 do
			world:fire("Punch", player, entry.id, 1)
		end
		world:advance(2)
		t.lte(session.data.stats.strikes, 8, "bounded by the cooldown and the token bucket")
		world:assertNoErrors()
	end)

	t.test("players without a loaded session cannot attack", function()
		local world, svc, player, session, entry = arena()
		local lurker = world:join(202)
		svc.Sessions.get(lurker).loaded = false
		world:placeCharacter(lurker, entry.center + Vector3.new(4, 0, 0))
		world:fire("Punch", lurker, entry.id, 1)
		world:advance(1)
		t.eq(entry.state.hp, entry.state.maxHp)
	end)

	t.test("swing effects reach only players near the attacker", function()
		local world, svc, player, session, entry = arena()
		local near = world:join(203)
		local far = world:join(204)
		world:placeCharacter(near, entry.center + Vector3.new(10, 0, 0))
		world:placeCharacter(far, entry.center + Vector3.new(900, 0, 0))
		world:clearSent()
		punch(world, player, entry, session)
		local function swings(p)
			local n = 0
			for _, args in world:sent("Fx", p) do
				if args[1] == "Swing" then
					n += 1
				end
			end
			return n
		end
		t.eq(swings(player), 1)
		t.eq(swings(near), 1)
		t.eq(swings(far), 0)
	end)

	t.test("equipping a different arm replaces the visible set and resets the combo", function()
		local world, svc, player, session, entry = arena("Alloy", "Ironvein")
		punch(world, player, entry, session)
		punch(world, player, entry, session)
		t.eq(session.combat.combo, 2)
		session.data.arms.owned.Magma = true
		session.data.arms.levels.Magma = 0
		t.truthy(world:invoke(player, "Equip", { armId = "Magma" }).ok)
		t.eq(session.data.arms.equipped, "Magma")
		t.eq(session.combat.armId, "Magma")
		t.eq(session.combat.combo, 0)
		local arms = 0
		for _, child in player.Character:GetChildren() do
			if child.Name == "ArmforgeArms" then
				arms += 1
			end
		end
		t.eq(arms, 1, "exactly one arm set on the character")
		t.eq(player.Character.ArmforgeArms:GetAttribute("ArmId"), "Magma")
		-- a rejected equip changes nothing
		local denied = world:invoke(player, "Equip", { armId = "Void" })
		t.eq(denied.ok, false)
		t.eq(session.data.arms.equipped, "Magma")
		t.eq(player.Character.ArmforgeArms:GetAttribute("ArmId"), "Magma")
		world:assertNoErrors()
	end)
end
