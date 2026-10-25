-- Arm signature moves: the data, the animation beats, and the server flow (rocks, creatures, bursts, cooldowns) on the fake server.
local roblox = require("@lune/roblox")
local ServerWorld = require("./support/ServerWorld")

return function(t, u)
	local Arms = u:load("Config/Arms")
	local Anim = u:load("Config/Animations")
	local SigConfig = u:load("Config/Signatures")
	local Signature = u:load("Logic/Signature")
	local PoseMath = u:load("Logic/PoseMath")
	local Combat = u:load("Logic/Combat")
	local V = roblox.Vector3

	-- Data ----------------------------------------------------------------------------------------------------------------------------

	t.test("every arm has a signature move with a real animation and a sane cooldown", function()
		local moves = PoseMath.moves()
		local seen = {}
		for _, armId in Arms.Order do
			local def = SigConfig.Defs[armId]
			t.truthy(def, armId .. " has a signature")
			t.eq(def.armId, armId)
			t.truthy(moves[def.move], armId .. " animation " .. def.move)
			t.truthy(def.cooldown >= 9 and def.cooldown <= 15, armId .. " cooldown")
			t.truthy(def.style ~= "" and not seen[def.style], armId .. " has its own visual style")
			seen[def.style] = true
			t.truthy(#def.strikes > 0 or def.burst ~= nil, armId .. " does something")
			t.eq(def.needsTarget, #def.strikes > 0, armId .. " needs a target exactly when it strikes one")
		end
		for armId in SigConfig.Defs do
			t.truthy(Arms.Defs[armId], armId .. " is a real arm")
		end
	end)

	t.test("a signature is worth a few times the arm's power, like the skills, and no more", function()
		for armId, def in SigConfig.Defs do
			local worth = Signature.worth(def)
			t.truthy(worth >= 1.6 and worth <= 6.5, `{armId} worth {worth}`)
			for _, s in def.strikes do
				t.truthy(s.mult > 0 and s.mult <= 4, armId .. " strike mult")
			end
		end
	end)

	t.test("strikes and bursts land inside the animation, on its beats", function()
		local moves = PoseMath.moves()
		for armId, def in SigConfig.Defs do
			local move = moves[def.move]
			local last = 0
			for _, s in def.strikes do
				t.truthy(s.at > last, armId .. " strikes ascend")
				last = s.at
				t.truthy(s.at <= move.duration, armId .. " strike inside the move")
				local near = false
				for _, k in move.keys do
					if math.abs(k.t - s.at / move.duration) < 0.03 then
						near = true
					end
				end
				t.truthy(near, `{armId}: a key pose within 0.03 of the strike at {s.at}s`)
			end
			if def.burst then
				t.truthy(def.burst.at <= move.duration, armId .. " burst inside the move")
				t.truthy(def.burst.at >= last, armId .. " burst follows the strikes")
				t.truthy(def.burst.center == "self" or def.burst.center == "target")
				t.truthy(def.burst.maxTargets >= 1 and def.burst.maxTargets <= 6)
				if #def.strikes == 0 then
					local near = false
					for _, k in move.keys do
						if math.abs(k.t - def.burst.at / move.duration) < 0.03 then
							near = true
						end
					end
					t.truthy(near, armId .. " burst on a key pose")
				end
			end
		end
	end)

	t.test("endurance shortens the signature cooldown like the skills", function()
		local data = u:load("Logic/DataSchema").default()
		local base = Signature.cooldown(data, "Magma")
		data.training.endurance.level = 10
		t.truthy(Signature.cooldown(data, "Magma") < base)
		t.truthy(Signature.cooldown(data, "Magma") >= base * 0.5)
		t.eq(Signature.cooldown(data, "Nope"), math.huge)
	end)

	-- Animation data ------------------------------------------------------------------------------------------------------------

	t.test("every pose joint is one the animator drives", function()
		local known = { Root = 1, Waist = 1, Neck = 1, RootPos = 1, RShoulder = 1, LShoulder = 1, RElbow = 1, LElbow = 1, RHip = 1, LHip = 1, RKnee = 1, LKnee = 1 }
		for name, move in PoseMath.moves() do
			for _, key in move.keys do
				for joint in key.pose do
					t.truthy(known[joint], `{name} uses unknown joint {joint}`)
				end
			end
		end
	end)

	t.test("combo chains keep the trait rhythms: Fists 3, Void ends on its Rend", function()
		t.eq(#Anim.Styles.Fists.moves, 3)
		t.eq(Anim.Styles.Fists.moves[3], "CrossR")
		t.eq(#Anim.Styles.Rend.moves, 4)
		t.eq(Anim.Styles.Rend.moves[4], "RendBoth")
		for style, def in Anim.Styles do
			t.truthy(#def.moves >= 3, style .. " has a real chain")
		end
	end)

	t.test("mirrored moves swap the legs as well as the arms", function()
		local hook = PoseMath.moves().HookR
		local mirrored = PoseMath.moves().HookL
		local right, left
		for _, k in hook.keys do
			if k.pose.RHip then
				right = k.pose.RHip
			end
		end
		for _, k in mirrored.keys do
			if k.pose.LHip then
				left = k.pose.LHip
			end
		end
		t.truthy(right and left)
		t.eq(left.X, right.X)
		t.eq(left.Z, -right.Z)
		t.eq(mirrored.hand, "L")
	end)

	-- Server flow ---------------------------------------------------------------------------------------------------------------

	local function arena(armId, rockId, userId)
		local world = ServerWorld.new()
		local svc = world:boot({ encounters = true })
		local player = world:join(userId or 701)
		local session = svc.Sessions.get(player)
		if armId ~= "Starter" then
			session.data.arms.owned[armId] = true
			session.data.arms.levels[armId] = 0
			t.truthy(world:invoke(player, "Equip", { armId = armId }).ok)
		end
		session.data.islands.unlocked.Forgeheart = true
		local entry = svc.RockService.spawnAt(rockId or "Granite", V.new(0, 0, 30), "Forgeheart")
		-- tough enough to outlast the whole move, so the test sees every strike
		entry.state.maxHp = 1e9
		entry.state.hp = 1e9
		world:placeCharacter(player, entry.center + V.new(4, 0, 0))
		world:advance(0.2)
		return world, svc, player, session, entry
	end

	local function fxCount(world, kind)
		local n = 0
		for _, args in world:sent("Fx") do
			if args[1] == kind then
				n += 1
			end
		end
		return n
	end

	local function used(world, player, rock)
		world:fire("Skill", player, "Signature", rock and rock.id or 0)
	end

	for _, armId in Arms.Order do
		local def = SigConfig.Defs[armId]
		if def.needsTarget then
			t.test(`{armId}: {def.name} strikes the rock it is aimed at and goes on cooldown`, function()
				local world, svc, player, session, entry = arena(armId, "Granite")
				local hp = entry.state.hp
				used(world, player, entry)
				world:advance(PoseMath.moves()[def.move].duration + 0.3)
				t.truthy(entry.state.hp < hp or not entry.state.alive, "damage landed")
				t.eq(fxCount(world, "Signature"), 1)
				t.truthy(Signature.remaining(session.combat, armId, world.sched.now) > 0, "on cooldown")
				t.truthy(session.data.stats.strikes >= #def.strikes, "every strike counted")
				world:assertNoErrors()
			end)
		end
	end

	t.test("a signature that needs a target costs nothing with none in reach", function()
		local world, svc, player, session = arena("Alloy", "Granite")
		used(world, player, nil)
		world:advance(1)
		t.eq(Signature.remaining(session.combat, "Alloy", world.sched.now), 0)
		t.eq(fxCount(world, "Signature"), 0)
		world:placeCharacter(player, V.new(200, 3, 200))
		local rock = svc.RockService.spawnAt("Granite", V.new(0, 0, 30), "Forgeheart")
		used(world, player, rock)
		world:advance(1)
		t.eq(Signature.remaining(session.combat, "Alloy", world.sched.now), 0, "out of reach")
		world:assertNoErrors()
	end)

	t.test("it cannot be spammed: the cooldown holds, per arm, and swapping arms never skips it", function()
		local world, svc, player, session, entry = arena("Starter", "Granite")
		used(world, player, entry)
		world:advance(0.1)
		used(world, player, entry)
		world:advance(1.3)
		t.eq(fxCount(world, "Signature"), 1, "the second press was refused")
		session.data.arms.owned.Stonebreaker = true
		session.data.arms.levels.Stonebreaker = 0
		t.truthy(world:invoke(player, "Equip", { armId = "Stonebreaker" }).ok)
		used(world, player, nil)
		world:advance(1.4)
		t.eq(fxCount(world, "Signature"), 2, "Stonebreaker has its own signature ready")
		t.truthy(world:invoke(player, "Equip", { armId = "Starter" }).ok)
		used(world, player, entry)
		world:advance(1.4)
		t.eq(fxCount(world, "Signature"), 2, "Starter is still cooling down")
		world:advance(Signature.cooldown(session.data, "Starter") + 1)
		used(world, player, entry)
		t.eq(fxCount(world, "Signature"), 3, "and ready again after its cooldown")
		world:assertNoErrors()
	end)

	t.test("garbage input is ignored", function()
		local world, svc, player, session = arena("Starter", "Granite")
		world:fire("Skill", player, "Signature", "x")
		world:fire("Skill", player, "Signature", -4)
		world:fire("Skill", player, "Signature", 0 / 0)
		world:fire("Skill", player, "Signature", 9e99)
		world:advance(1)
		t.eq(fxCount(world, "Signature"), 0)
		world:assertNoErrors()
	end)

	t.test("Quake Stomp needs no target: it batters the rocks and creatures around the wearer", function()
		local world, svc, player, session, entry = arena("Stonebreaker", "Granite")
		local second = svc.RockService.spawnAt("Granite", V.new(0, 0, 38), "Forgeheart")
		local hp1, hp2 = entry.state.hp, second.state.hp
		used(world, player, nil)
		world:advance(1.3)
		t.truthy(entry.state.hp < hp1 and second.state.hp < hp2, "both rocks hit")
		t.eq(fxCount(world, "Burst"), 1)
		world:placeCharacter(player, V.new(300, 3, 300))
		world:advance(Signature.cooldown(session.data, "Stonebreaker") + 1)
		used(world, player, nil)
		world:advance(1.3)
		t.eq(fxCount(world, "Burst"), 2, "a quake in the open still goes off")
		world:assertNoErrors()
	end)

	t.test("Prism Lance refracts into the neighbours but never the rock it struck", function()
		local world, svc, player, session, entry = arena("Crystal", "Granite")
		local near = svc.RockService.spawnAt("Granite", V.new(6, 0, 30), "Forgeheart")
		local far = svc.RockService.spawnAt("Granite", V.new(60, 0, 30), "Forgeheart")
		near.state.maxHp = 1e9
		near.state.hp = 1e9
		local hpNear, hpFar = near.state.hp, far.state.hp
		used(world, player, entry)
		world:advance(1.5)
		t.truthy(near.state.hp < hpNear, "the neighbour was hit by the burst")
		t.eq(far.state.hp, hpFar, "the far rock was out of the burst")
		t.eq(fxCount(world, "Burst"), 1)
		world:assertNoErrors()
	end)

	t.test("Eruption sets rocks alight", function()
		local world, svc, player, session, entry = arena("Magma", "Granite")
		local near = svc.RockService.spawnAt("Granite", V.new(6, 0, 30), "Forgeheart")
		near.state.maxHp = 1e9
		near.state.hp = 1e9
		used(world, player, entry)
		world:advance(1.3)
		t.truthy(entry.burn ~= nil or not entry.state.alive, "the struck rock is burning")
		t.truthy(near.burn ~= nil, "and so is its neighbour")
		world:assertNoErrors()
	end)

	t.test("Piston Storm leaves Overclock at full stacks", function()
		local world, svc, player, session, entry = arena("Alloy", "Granite")
		used(world, player, entry)
		world:advance(1.6)
		t.eq(session.combat.overclock, 5)
		local stats = Combat.stats(session.data, session.combat, world.sched.now)
		local base = Combat.stats(session.data, Combat.newState("Alloy"), world.sched.now)
		t.truthy(stats.cooldown < base.cooldown, "faster than a cold Alloy")
		world:assertNoErrors()
	end)

	t.test("swapping arms mid-move cancels the rest of the strikes", function()
		local world, svc, player, session, entry = arena("Starter", "Granite")
		local hp = entry.state.hp
		used(world, player, entry)
		world:advance(0.3) -- the first jab has landed
		local afterFirst = entry.state.hp
		t.truthy(afterFirst < hp)
		session.data.arms.owned.Alloy = true
		session.data.arms.levels.Alloy = 0
		t.truthy(world:invoke(player, "Equip", { armId = "Alloy" }).ok)
		world:advance(1.5)
		t.eq(entry.state.hp, afterFirst, "nothing landed after the swap")
		world:assertNoErrors()
	end)

	t.test("signatures work on creatures too, and respect armor", function()
		local world, svc, player, session = arena("Starter", "Granite")
		local rock = svc.RockService.spawnAt("Ironvein", V.new(0, 0, 60), "Forgeheart")
		world:placeCharacter(player, rock.base.Position + V.new(6, 3, 0))
		svc.RockService.damage(rock, player, player.UserId, rock.state.maxHp * 2, {})
		world:advance(4.5)
		local enc = svc.EncounterService.get(rock.id)
		t.truthy(enc and enc.sim)
		local hp = enc.sim.hp
		used(world, player, rock)
		world:advance(1.5)
		t.truthy(enc.sim.hp < hp, "the creature took damage")
		world:assertNoErrors()
	end)

	t.test("the Fx a signature sends carry what the client needs", function()
		local world, svc, player, session, entry = arena("Void", "Granite")
		used(world, player, entry)
		world:advance(1.6)
		local payload
		for _, args in world:sent("Fx") do
			if args[1] == "Signature" then
				payload = args[2]
			end
		end
		t.truthy(payload)
		t.eq(payload.arm, "Void")
		t.eq(payload.move, "RiftTear")
		t.eq(payload.style, "rift")
		t.eq(payload.u, player.UserId)
		t.eq(payload.rock, entry.id)
		t.truthy(payload.tp)
		world:assertNoErrors()
	end)

	t.test("developer mode can clear every cooldown for back-to-back testing", function()
		local world = ServerWorld.new({ studio = true })
		local svc = world:boot({ encounters = true })
		local player = world:join(777)
		local session = svc.Sessions.get(player)
		local rock = svc.RockService.spawnAt("Granite", V.new(0, 0, 30), "Forgeheart")
		rock.state.maxHp = 1e9
		rock.state.hp = 1e9
		world:placeCharacter(player, rock.center + V.new(4, 0, 0))
		used(world, player, rock)
		world:advance(1.4)
		t.truthy(Signature.remaining(session.combat, "Starter", world.sched.now) > 0)
		t.truthy(world:invoke(player, "Dev", { line = "resetcd" }).ok)
		t.eq(Signature.remaining(session.combat, "Starter", world.sched.now), 0)
		world:assertNoErrors()
	end)
end
