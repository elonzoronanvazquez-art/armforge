-- Developer mode: who may use it, what the data commands do (and refuse to do), and the server integration. A hostile or unauthorized client
-- must get nothing; an authorized tester must be able to skip the grind without ever corrupting a profile.
local roblox = require("@lune/roblox")
local ServerWorld = require("./support/ServerWorld")

return function(t, u)
	local Access = u:load("Logic/DevAccess")
	local Cmd = u:load("Logic/DevCommands")
	local Schema = u:load("Logic/DataSchema")
	local Persistence = u:load("Logic/Persistence")
	local IslandCfg = u:load("Config/Islands")
	local Arms = u:load("Config/Arms")
	local Skills = u:load("Config/Skills")
	local ProgressionCfg = u:load("Config/Progression")
	local V = roblox.Vector3

	local function facts(over)
		local f = { studio = false, userId = 100, creatorIsUser = true, creatorId = 5, groupRank = 0, allowedUserIds = {}, allowCreator = true }
		for k, v in over or {} do
			f[k] = v
		end
		return f
	end

	-- Access --------------------------------------------------------------------------------------------------------------------

	t.test("access: Studio, listed ids and the place owner; nobody else", function()
		t.eq(Access.decide(facts({ studio = true })), true, "any Studio session")
		t.eq(Access.decide(facts()), false, "a stranger in a live server")
		t.eq(Access.decide(facts({ allowedUserIds = { 7, 100 } })), true, "a listed id")
		t.eq(Access.decide(facts({ allowedUserIds = { 7 } })), false, "an id that is not listed")
		t.eq(Access.decide(facts({ userId = 5 })), true, "the owner of a user-owned place")
		t.eq(Access.decide(facts({ userId = 5, allowCreator = false })), false, "owner access can be switched off")
		t.eq(Access.decide(facts({ creatorIsUser = false, creatorId = 99, groupRank = 255 })), true, "the owner of a group place")
		t.eq(Access.decide(facts({ creatorIsUser = false, creatorId = 99, groupRank = 254 })), false, "an admin is not the owner")
		t.eq(Access.decide(facts({ creatorIsUser = false, creatorId = 99, groupRank = 0, userId = 99 })), false, "a group id is never a user id")
		t.eq(Access.decide(facts({ userId = 0, creatorId = 0 })), false, "an unpublished place grants nothing by itself")
	end)

	-- Commands: parsing ---------------------------------------------------------------------------------------------------------------

	t.test("a command line is split into a lowercase name and its words", function()
		local name, args = Cmd.parse("  COINS   5000 ")
		t.eq(name, "coins")
		t.deepEq(args, { "5000" })
		local empty, none = Cmd.parse("   ")
		t.eq(empty, "")
		t.deepEq(none, {})
	end)

	-- Commands: data --------------------------------------------------------------------------------------------------------------------

	local function fresh()
		return Schema.default()
	end

	local function run(d, line)
		local name, args = Cmd.parse(line)
		return Cmd.apply(d, name, args)
	end

	t.test("coins and shards add (negative removes) and never go below zero or above the cap", function()
		local d = fresh()
		t.truthy(run(d, "coins 5000").ok)
		t.eq(d.coins, 5000)
		t.truthy(run(d, "coins -2000").ok)
		t.eq(d.coins, 3000)
		run(d, "coins -999999")
		t.eq(d.coins, 0, "never negative")
		run(d, "setcoins 1e15")
		t.eq(d.coins, 1e15)
		run(d, "coins 1e15")
		run(d, "coins 1e15")
		t.truthy(d.coins <= 9e15, "capped at what a double represents exactly")
		t.truthy(run(d, "shards 40").ok)
		t.eq(d.shards, 40)
	end)

	t.test("xp levels up through the real rules; level sets exactly, up or down", function()
		local d = fresh()
		t.truthy(run(d, "xp 100000").ok)
		t.truthy(d.level > 1, "xp levels up")
		t.truthy(d.skillPoints >= d.level - 1, "with the skill points of those levels")
		local d2 = fresh()
		t.truthy(run(d2, "level 12").ok)
		t.eq(d2.level, 12)
		t.truthy(d2.skillPoints >= 11)
		t.truthy(run(d2, "level 40").ok)
		t.eq(d2.level, ProgressionCfg.MaxLevel)
		t.truthy(run(d2, "level 5").ok)
		t.eq(d2.level, 5)
		t.eq(d2.xp, 0)
	end)

	t.test("rebirths are set within the allowed range", function()
		local d = fresh()
		t.truthy(run(d, "rebirths 4").ok)
		t.eq(d.rebirths, 4)
		t.eq(run(d, "rebirths 9999").ok, false)
		t.eq(d.rebirths, 4, "a refused command changes nothing")
		t.eq(run(d, "rebirths -1").ok, false)
	end)

	t.test("unlockislands opens every playable island and never a coming-soon one", function()
		local d = fresh()
		t.truthy(run(d, "unlockislands").ok)
		for id, def in IslandCfg.Defs do
			t.eq(d.islands.unlocked[id] == true, not def.comingSoon, id)
		end
		-- the real gate logic agrees: they can all be travelled to
		local Islands = u:load("Logic/Islands")
		for id, def in IslandCfg.Defs do
			if not def.comingSoon then
				t.truthy(Islands.canTravel(d, id).ok, id)
			end
		end
	end)

	t.test("guardians, arms, skills and boosters", function()
		local d = fresh()
		run(d, "completeguardians")
		for id, def in IslandCfg.Defs do
			t.eq(d.guardians.defeated[id] == true, def.guardian ~= nil, id)
		end
		t.truthy(run(d, "maxarms").ok)
		for id, def in Arms.Defs do
			t.eq(d.arms.owned[id], true, id)
			t.eq(d.arms.levels[id], def.maxLevel, id)
		end
		run(d, "skills")
		for id, def in Skills.Defs do
			t.eq(d.skills.ranks[id], def.maxRank, id)
		end
		run(d, "boosters 2")
		local any = false
		for _, n in d.boosters.inventory do
			any = true
			t.eq(n >= 2, true)
		end
		t.truthy(any)
	end)

	t.test("the test kit gets a new profile ready for late content, and the result is a valid profile", function()
		local d = fresh()
		t.truthy(run(d, "kit").ok)
		t.eq(d.level, ProgressionCfg.MaxLevel)
		t.truthy(d.coins >= 1e9 and d.shards >= 500 and d.rebirths >= 6)
		t.eq(d.islands.unlocked.Dustwake, true)
		t.eq(d.islands.unlocked.Voidreach, nil)
		-- it survives a save / load round trip unchanged where it matters
		local back = Schema.reconcile(Persistence.deepCopy(d))
		t.eq(back.level, d.level)
		t.eq(back.rebirths, d.rebirths)
		t.eq(back.islands.unlocked.Cogspire, true)
		for id, def in Arms.Defs do
			t.eq(back.arms.levels[id], def.maxLevel, id)
		end
	end)

	t.test("bad input is refused with a usage message and changes nothing", function()
		local d = fresh()
		local before = Persistence.deepCopy(d)
		for _, line in { "coins", "coins abc", "coins 1e99", "coins nan", "coins inf", "level 0", "level 41", "level 3.5x", "xp -5", "rebirths", "nope", "", "kit; coins 5" } do
			local result = run(d, line)
			if line ~= "kit; coins 5" then
				t.eq(result.ok, false, `"{line}"`)
			end
		end
		t.deepEq(d, before)
	end)

	-- Server integration -----------------------------------------------------------------------------------------------------------

	local function setup(opts, userId)
		local world = ServerWorld.new(opts)
		local svc = world:boot({ encounters = true })
		local player = world:join(userId or 801)
		return world, svc, player, svc.Sessions.get(player), world:shared("Config/Game")
	end

	t.test("an unauthorized player gets nothing from the Dev request, however it is phrased", function()
		local world, svc, player, session = setup({ studio = false })
		local before = session.data.coins
		local r = world:invoke(player, "Dev", { line = "coins 99999" })
		t.eq(r.ok, false)
		t.eq(session.data.coins, before)
		for _, line in { "kit", "unlockislands", "level 40", "god", "power 1000", "goto Dustwake", "reset confirm" } do
			t.eq(world:invoke(player, "Dev", { line = line }).ok, false, line)
		end
		t.eq(session.data.level, 1)
		t.eq(session.data.islands.unlocked.Dustwake, nil)
		t.eq(session.flags.devGod, nil)
		t.eq(Persistence.deepCopy(session.data).coins, before)
		-- the client is never told developer mode exists
		local snap
		for _, args in world:sent("Sync", player) do
			snap = args[1]
		end
		t.truthy(snap == nil or snap.live == nil or snap.live.dev ~= true)
		world:assertNoErrors()
	end)

	t.test("hostile payloads never error the handler", function()
		local world, svc, player, session, Game = setup({ studio = true })
		for _, args in { {}, { line = 5 }, { line = {} }, { line = string.rep("x", 500) }, { line = "" }, { line = "coins " .. string.rep("9", 80) }, "string", 7 } do
			local r = world:invoke(player, "Dev", args)
			t.eq(r.ok, false)
		end
		world:assertNoErrors()
	end)

	t.test("in Studio every command works, and the Sync snapshot tells the client", function()
		local world, svc, player, session = setup({ studio = true })
		t.truthy(world:invoke(player, "Dev", { line = "coins 12345" }).ok)
		t.eq(session.data.coins, 12345)
		t.truthy(world:invoke(player, "Dev", { line = "unlockall" }).ok)
		t.eq(session.data.islands.unlocked.Cogspire, true)
		t.truthy(world:invoke(player, "Dev", { line = "level 20" }).ok)
		t.eq(session.data.level, 20)
		local snap
		for _, args in world:sent("Sync", player) do
			snap = args[1]
		end
		t.eq(snap.live.dev, true)
		t.eq(snap.level, 20)
		world:assertNoErrors()
	end)

	t.test("a listed UserId may use it in a live server; others still may not", function()
		local world = ServerWorld.new({ studio = false })
		local svc = world:boot({ encounters = true })
		local Game = world:shared("Config/Game")
		table.insert(Game.Dev.allowedUserIds, 812)
		local tester = world:join(812)
		local other = world:join(813)
		t.truthy(world:invoke(tester, "Dev", { line = "coins 10" }).ok)
		t.eq(svc.Sessions.get(tester).data.coins, 10)
		t.eq(world:invoke(other, "Dev", { line = "coins 10" }).ok, false)
		t.eq(svc.Sessions.get(other).data.coins, 0)
		world:assertNoErrors()
	end)

	t.test("the kit wears the strongest arm; equip switches between owned arms and refuses the rest", function()
		local world, svc, player, session = setup({ studio = true })
		t.eq(world:invoke(player, "Dev", { line = "equip void" }).ok, false, "not owned yet")
		t.truthy(world:invoke(player, "Dev", { line = "kit" }).ok)
		t.eq(session.data.arms.equipped, "Void")
		t.truthy(world:invoke(player, "Dev", { line = "equip STARTER" }).ok)
		t.eq(session.data.arms.equipped, "Starter")
		t.eq(world:invoke(player, "Dev", { line = "equip nothing" }).ok, false)
		world:assertNoErrors()
	end)

	t.test("goto moves the player to an island's arrival, opening it", function()
		local world, svc, player, session = setup({ studio = true })
		t.eq(session.data.islands.unlocked.Dustwake, nil)
		local r = world:invoke(player, "Dev", { line = "goto dustwake" })
		t.truthy(r.ok, tostring(r.msg))
		t.eq(session.data.islands.current, "Dustwake")
		t.eq(session.data.islands.unlocked.Dustwake, true)
		local pos = player.Character.HumanoidRootPart.CFrame.Position
		local arrival = IslandCfg.Defs.Dustwake.arrival
		t.truthy((V.new(pos.X, 0, pos.Z) - V.new(arrival.X, 0, arrival.Z)).Magnitude < 20, "stands at the arrival point")
		t.eq(world:invoke(player, "Dev", { line = "goto Voidreach" }).ok, false, "a coming-soon island cannot be entered")
		t.eq(world:invoke(player, "Dev", { line = "goto Atlantis" }).ok, false)
		world:assertNoErrors()
	end)

	t.test("power multiplies the damage dealt to rocks, god switches creature damage off, both only for that player", function()
		local world, svc, player, session = setup({ studio = true })
		local other = world:join(802)
		local a = svc.RockService.spawnAt("Granite", V.new(0, 0, 40), "Forgeheart")
		local b = svc.RockService.spawnAt("Granite", V.new(60, 0, 40), "Forgeheart")
		world:placeCharacter(player, V.new(0, 3, 30))
		world:placeCharacter(other, V.new(60, 3, 30))
		svc.RockService.damage(a, player, player.UserId, 10, {})
		local plain = a.state.maxHp - a.state.hp
		svc.RockService.damage(b, other, other.UserId, 10, {})
		t.eq(b.state.maxHp - b.state.hp, plain)
		local c = svc.RockService.spawnAt("Granite", V.new(120, 0, 40), "Forgeheart")
		t.truthy(world:invoke(player, "Dev", { line = "power 4" }).ok)
		world:placeCharacter(player, V.new(120, 3, 30))
		svc.RockService.damage(c, player, player.UserId, 10, {})
		t.near(c.state.maxHp - c.state.hp, plain * 4, 0.5)
		t.eq(world:invoke(player, "Dev", { line = "power 0" }).ok, false, "power must be at least 1")
		t.truthy(world:invoke(player, "Dev", { line = "god" }).ok)
		t.eq(session.flags.devGod, true)
		t.eq(svc.Sessions.get(other).flags.devGod, nil)
		t.truthy(world:invoke(player, "Dev", { line = "god off" }).ok)
		t.eq(session.flags.devGod, nil)
		world:assertNoErrors()
	end)

	t.test("reset needs an explicit confirmation and then returns a brand new profile", function()
		local world, svc, player, session = setup({ studio = true })
		world:invoke(player, "Dev", { line = "kit" })
		t.eq(session.data.level, ProgressionCfg.MaxLevel)
		local r = world:invoke(player, "Dev", { line = "reset" })
		t.eq(r.ok, false)
		t.eq(session.data.level, ProgressionCfg.MaxLevel, "nothing happened without the confirmation")
		t.truthy(world:invoke(player, "Dev", { line = "reset confirm" }).ok)
		t.eq(session.data.level, 1)
		t.eq(session.data.coins, 0)
		t.eq(session.data.rebirths, 0)
		t.eq(session.data.islands.unlocked.Dustwake, nil)
		t.eq(session.data.islands.current, "Forgeheart")
		t.eq(session.data.arms.equipped, "Starter")
		world:assertNoErrors()
	end)

	t.test("momentum can be granted for testing the mountain, and the command list is discoverable", function()
		local world, svc, player, session = setup({ studio = true })
		t.truthy(world:invoke(player, "Dev", { line = "momentum" }).ok)
		t.truthy(session.momentum ~= nil)
		local help = world:invoke(player, "Dev", { line = "help" })
		t.truthy(help.ok)
		for _, name in { "coins", "xp", "level", "kit", "goto", "god", "power", "reset", "unlockislands" } do
			t.truthy(string.find(help.msg, name, 1, true), name)
		end
		world:assertNoErrors()
	end)
end
