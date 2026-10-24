-- Requests / ArmService / ProgressionServices glue on the fake server: validation, rate limits, purchases,
-- location-gated actions, and what a client can never make the server do.
local roblox = require("@lune/roblox")
local ServerWorld = require("./support/ServerWorld")

return function(t, u)
	local Game = u:load("Config/Game")
	local V = roblox.Vector3

	local function setup()
		local world = ServerWorld.new()
		local svc = world:boot()
		local player = world:join(401)
		return world, svc, player, svc.Sessions.get(player)
	end

	t.test("unknown, malformed and non-table requests are rejected without errors", function()
		local world, svc, player = setup()
		t.eq(world:invoke(player, "Teleport", {}).err, "unknown_action")
		t.eq(world:invoke(player, 12345, {}).err, "bad_request")
		t.eq(world:invoke(player, nil, nil).err, "bad_request")
		t.eq(world:invoke(player, {}, {}).err, "bad_request")
		t.eq(world:invoke(player, ("x"):rep(500), {}).err, "bad_request")
		t.eq(world:invoke(player, "Equip", "not a table").err, "bad_args")
		t.eq(world:invoke(player, "Equip", { armId = 42 }).err, "bad_args")
		t.eq(world:invoke(player, "BuyArm", { armId = { "x" } }).err, "bad_args")
		world:assertNoErrors()
	end)

	t.test("a client cannot set arbitrary data through SetSetting", function()
		local world, svc, player, session = setup()
		t.eq(world:invoke(player, "SetSetting", { key = "coins", value = 1e9 }).ok, false)
		t.eq(world:invoke(player, "SetSetting", { key = "sfx", value = 99 }).ok, false)
		t.eq(world:invoke(player, "SetSetting", { key = "sfx", value = 0 / 0 }).ok, false)
		t.eq(world:invoke(player, "SetSetting", { key = "reduceFx", value = "yes" }).ok, false)
		t.eq(world:invoke(player, "SetSetting", { key = "sfx", value = 0.25 }).ok, true)
		t.eq(session.data.settings.sfx, 0.25)
		t.eq(session.data.coins, Game.Start.coins)
		t.eq(session.data.settings.coins, nil)
	end)

	t.test("request spam is rate limited", function()
		local world, svc, player = setup()
		local limited = 0
		for _ = 1, 60 do
			if world:invoke(player, "SetSetting", { key = "sfx", value = 0.5 }).err == "slow_down" then
				limited += 1
			end
		end
		t.truthy(limited >= 40, `only {limited} of 60 were throttled`)
	end)

	t.test("buying an arm needs the money, charges once, and a double-click cannot buy it twice", function()
		local world, svc, player, session = setup()
		local denied = world:invoke(player, "BuyArm", { armId = "Stonebreaker" })
		t.eq(denied.ok, false)
		t.eq(session.data.arms.owned.Stonebreaker, nil)
		t.eq(session.data.coins, Game.Start.coins, "a failed purchase costs nothing")
		session.data.coins = 20000
		session.data.level = 3
		local first = world:invoke(player, "BuyArm", { armId = "Stonebreaker" })
		local second = world:invoke(player, "BuyArm", { armId = "Stonebreaker" })
		t.eq(first.ok, true)
		t.eq(second.ok, false)
		t.eq(session.data.coins, 20000 - 900)
		world:assertNoErrors()
	end)

	t.test("equip, upgrade and cosmetic changes keep exactly one visible arm set in sync with the data", function()
		local world, svc, player, session = setup()
		session.data.coins = 5e6
		session.data.arms.owned.Alloy = true
		session.data.arms.levels.Alloy = 0
		t.truthy(world:invoke(player, "Equip", { armId = "Alloy" }).ok)
		local function sets()
			local n = 0
			for _, child in player.Character:GetChildren() do
				if child.Name == "ArmforgeArms" then
					n += 1
				end
			end
			return n
		end
		t.eq(sets(), 1)
		local attached = #world.armAttachments
		local up = world:invoke(player, "UpgradeArm", { armId = "Alloy" })
		t.truthy(up.ok)
		t.eq(session.data.arms.levels.Alloy, 1)
		t.eq(#world.armAttachments, attached + 1, "the equipped arm is rebuilt after an upgrade")
		t.eq(sets(), 1, "the old set was replaced, not stacked")
		-- upgrading an arm that is not equipped does not touch the character
		session.data.arms.owned.Magma = true
		session.data.arms.levels.Magma = 0
		local before = #world.armAttachments
		t.truthy(world:invoke(player, "UpgradeArm", { armId = "Magma" }).ok)
		t.eq(#world.armAttachments, before)
		-- equipping something not owned changes nothing
		t.eq(world:invoke(player, "Equip", { armId = "Void" }).ok, false)
		t.eq(session.data.arms.equipped, "Alloy")
		t.eq(player.Character.ArmforgeArms:GetAttribute("ArmId"), "Alloy")
		world:assertNoErrors()
	end)

	t.test("a respawned character gets the equipped arm set again", function()
		local world, svc, player, session = setup()
		session.data.arms.owned.Alloy = true
		session.data.arms.levels.Alloy = 0
		world:invoke(player, "Equip", { armId = "Alloy" })
		player:LoadCharacterAsync()
		world:advance(1)
		t.eq(player.Character.ArmforgeArms:GetAttribute("ArmId"), "Alloy")
		world:assertNoErrors()
	end)

	t.test("every successful request pushes a fresh snapshot to that player only", function()
		local world, svc, player, session = setup()
		local other = world:join(402)
		world:clearSent()
		session.data.coins = 20000
		session.data.level = 3
		world:invoke(player, "BuyArm", { armId = "Stonebreaker" })
		local mine = world:sent("Sync", player)
		t.eq(#mine, 1)
		t.eq(mine[1][1].arms.owned.Stonebreaker, true)
		t.eq(#world:sent("Sync", other), 0)
		-- a failed request sends nothing
		world:clearSent()
		world:invoke(player, "BuyArm", { armId = "Void" })
		t.eq(#world:sent("Sync", player), 0)
	end)

	t.test("travel and island unlock only work at a Skyport terminal", function()
		local world, svc, player, session = setup()
		world:placeCharacter(player, V.new(0, 3, 0))
		t.eq(world:invoke(player, "Travel", { islandId = "Mossveil" }).err, "not_at_skyport")
		t.eq(world:invoke(player, "UnlockIsland", { islandId = "Mossveil" }).err, "not_at_skyport")
		world:addTagged("Skyport", V.new(10, 0, 10))
		-- near a terminal but not yet qualified
		local early = world:invoke(player, "UnlockIsland", { islandId = "Mossveil" })
		t.eq(early.ok, false)
		t.eq(session.data.islands.unlocked.Mossveil, nil)
		session.data.level = 5
		session.data.coins = 1e6
		local gated = world:invoke(player, "UnlockIsland", { islandId = "Mossveil" })
		t.eq(gated.ok, false, "level alone does not open the next island")
		session.data.rebirths = 1
		t.eq(world:invoke(player, "UnlockIsland", { islandId = "Mossveil" }).ok, false, "a rebirth alone does not either")
		session.data.guardians.defeated.Forgeheart = true
		local unlock = world:invoke(player, "UnlockIsland", { islandId = "Mossveil" })
		t.eq(unlock.ok, true, tostring(unlock.err))
		local pos = player.Character.HumanoidRootPart.Position
		local travel = world:invoke(player, "Travel", { islandId = "Mossveil" })
		t.eq(travel.ok, true, tostring(travel.err))
		t.eq(session.data.islands.current, "Mossveil")
		t.truthy((player.Character.HumanoidRootPart.Position - pos).Magnitude > 50, "moved to the arrival point")
		-- a locked island cannot be travelled to even next to a terminal
		t.eq(world:invoke(player, "Travel", { islandId = "Crystalfall" }).ok, false)
		t.eq(session.data.islands.current, "Mossveil")
		world:assertNoErrors()
	end)

	t.test("rebirth requires the altar and the level; a failed attempt changes nothing", function()
		local world, svc, player, session = setup()
		world:placeCharacter(player, V.new(0, 3, 0))
		t.eq(world:invoke(player, "Rebirth", {}).err, "not_at_altar")
		world:addTagged("RebirthAltar", V.new(5, 0, 5))
		session.data.level = 3
		session.data.coins = 777
		local result = world:invoke(player, "Rebirth", {})
		t.eq(result.ok, false)
		t.eq(session.data.rebirths, 0)
		t.eq(session.data.level, 3)
		t.eq(session.data.coins, 777)
	end)

	t.test("players without a ready session get not_ready, and nothing errors after they leave", function()
		local world, svc, player, session = setup()
		session.loaded = false
		t.eq(world:invoke(player, "Equip", { armId = "Starter" }).err, "not_ready")
		t.eq(world:invoke(player, "TutorialAck", {}).err, "not_ready")
		session.loaded = true
		world:leave(player)
		t.eq(world:invoke(player, "Equip", { armId = "Starter" }).err, "not_ready")
		t.eq(world:invoke(player, "BuyArm", { armId = "Alloy" }).err, "not_ready")
		world:assertNoErrors()
	end)

	t.test("rate limiter buckets are released when a player leaves", function()
		local world, svc, player = setup()
		for _ = 1, 20 do
			world:invoke(player, "SetSetting", { key = "sfx", value = 0.5 })
		end
		world:leave(player)
		local again = world:join(401)
		t.eq(world:invoke(again, "SetSetting", { key = "sfx", value = 0.5 }).ok, true)
	end)

	t.test("marking state dirty many times produces one coalesced snapshot per interval", function()
		local world, svc, player = setup()
		world:clearSent()
		for _ = 1, 50 do
			svc.Sync.mark(player)
		end
		world:advance(0.2)
		world:fireHeartbeat()
		world:fireHeartbeat()
		t.eq(#world:sent("Sync", player), 1)
		world:fireHeartbeat()
		t.eq(#world:sent("Sync", player), 1, "nothing is resent while clean")
	end)

	t.test("a leaving player is never synced and sync errors never escape", function()
		local world, svc, player, session = setup()
		svc.Sync.mark(player)
		session.leaving = true
		world:clearSent()
		world:advance(0.2)
		world:fireHeartbeat()
		t.eq(#world:sent("Sync", player), 0)
		world:assertNoErrors()
	end)
end
