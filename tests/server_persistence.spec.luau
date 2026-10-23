-- Persistence glue (PlayerService + DataService + Persistence + Sessions) against a fake DataStore with latency and
-- failure injection. SIMULATED persistence: it proves the logic around the store, not Roblox's real DataStore.
local ServerWorld = require("./support/ServerWorld")

local PROD = "ARMFORGE_PlayerData/v1"
local STUDIO = "ARMFORGE_PlayerData_Studio/v1"

return function(t, u)
	local Game = u:load("Config/Game")

	local function boot(opts)
		local world = ServerWorld.new(opts)
		local svc = world:boot()
		return world, svc
	end

	local function record(world, userId, name)
		return world.stores[name or PROD].data[`Player_{userId}`]
	end

	t.test("a new player gets a default profile and a session lock for this server", function()
		local world, svc = boot()
		local player = world:join(101)
		local session = svc.Sessions.get(player)
		t.truthy(session and session.loaded, "session loaded")
		t.eq(session.data.coins, Game.Start.coins)
		t.eq(player.leaderstats.Level.Value, 1)
		local rec = world.stores[PROD].data.Player_101
		t.eq(rec.lock.jobId, "job-A")
		world:assertNoErrors()
	end)

	t.test("progress survives leave and rejoin; the lock is released on leave", function()
		local world, svc = boot()
		local player = world:join(102)
		local data = svc.Sessions.get(player).data
		data.coins = 777
		data.level = 5
		data.arms.owned.Magma = true
		data.arms.levels.Magma = 4
		data.arms.equipped = "Magma"
		world:leave(player)
		local rec = record(world, 102)
		t.eq(rec.lock, nil, "lock released")
		t.eq(rec.data.coins, 777)
		local again = world:join(102)
		local back = svc.Sessions.get(again).data
		t.eq(back.coins, 777)
		t.eq(back.level, 5)
		t.eq(back.arms.equipped, "Magma")
		t.eq(back.arms.levels.Magma, 4)
		world:assertNoErrors()
	end)

	t.test("a failed load kicks the player and never writes defaults over the saved profile", function()
		local world, svc = boot()
		local first = world:join(103)
		svc.Sessions.get(first).data.coins = 4242
		world:leave(first)
		local store = world.stores[PROD]
		local before = u:clone(store.data.Player_103)
		local commits = store.commits

		store.failAll = true
		local player = world:join(103)
		world:advance(120)
		t.truthy(world.kicked[103], "player kicked when the save cannot be loaded safely")
		t.eq(svc.Sessions.get(player), nil, "no live session")
		t.eq(store.commits, commits, "nothing was written during the outage")

		store.failAll = false
		t.deepEq(store.data.Player_103, before, "stored profile untouched")
		local back = world:join(103)
		t.eq(svc.Sessions.get(back).data.coins, 4242, "rejoin after the outage restores the real profile")
		world:assertNoErrors()
	end)

	t.test("a profile locked by another live server is not loaded or modified", function()
		local world, svc = boot()
		local store = world.stores[PROD]
		store.data.Player_104 = {
			data = { coins = 999, level = 3 },
			lock = { jobId = "job-OTHER", time = world:time() },
			savedAt = world:time(),
			schema = Game.Data.schemaVersion,
		}
		local before = u:clone(store.data.Player_104)
		local player = world:join(104)
		world:advance(120)
		t.truthy(world.kicked[104])
		t.eq(svc.Sessions.get(player), nil)
		t.deepEq(store.data.Player_104, before)
		world:assertNoErrors()
	end)

	t.test("leaving while the load is in flight releases the lock", function()
		local world, svc = boot()
		local store = world.stores[PROD]
		store.latency = 2
		local player = world:join(105)
		world:advance(1) -- UpdateAsync (the load) is pending
		world:leave(player)
		world:advance(10)
		t.eq(svc.Sessions.get(player), nil)
		local rec = store.data.Player_105
		t.truthy(rec == nil or rec.lock == nil, "no leaked lock")
		world:assertNoErrors()
	end)

	t.test("PlayerRemoving firing before the load completes (player still parented) releases the lock", function()
		local world, svc = boot()
		local store = world.stores[PROD]
		store.latency = 2
		local player = world:join(106)
		world:advance(1)
		world:beginLeave(player) -- handlers ran, but the player has not detached yet
		world:advance(2.5) -- the load finishes in this window
		world:finishLeave(player)
		world:advance(10)
		local rec = store.data.Player_106
		t.truthy(rec == nil or rec.lock == nil, "lock released even though the abort path saw a parented player")
		t.eq(svc.Sessions.get(player), nil)
		t.eq(player.Character, nil, "no character spawned for a player who left")
		world:assertNoErrors()
	end)

	t.test("autosave in flight when the player leaves cannot restore the released lock", function()
		local world, svc = boot()
		local store = world.stores[PROD]
		local player = world:join(107)
		local session = svc.Sessions.get(player)
		store.latency = 1
		world:advance(Game.Data.autosaveInterval + 0.2) -- autosave started, UpdateAsync pending
		session.data.coins = 321
		world:leave(player) -- release must queue behind the autosave
		world:advance(10)
		local rec = store.data.Player_107
		t.eq(rec.lock, nil, "lock stays released")
		t.eq(rec.data.coins, 321, "the leave-save carried the latest data")
		world:assertNoErrors()
	end)

	t.test("a session that is leaving never takes the lock again via a late autosave", function()
		local world, svc = boot()
		local store = world.stores[PROD]
		local player = world:join(108)
		local session = svc.Sessions.get(player)
		world:leave(player)
		local calls = #store.calls
		local DataService = world:load("Services/DataService")
		local handle = world:run(DataService.save, session, false)
		world:advance(1)
		t.eq(handle.results[1], false)
		t.eq(#store.calls, calls, "no store traffic")
		t.eq(store.data.Player_108.lock, nil)
	end)

	t.test("save failures are reported, counted and recover; a failed save is never reported as success", function()
		local world, svc = boot()
		local store = world.stores[PROD]
		local player = world:join(109)
		local session = svc.Sessions.get(player)
		local DataService = world:load("Services/DataService")
		store.failAll = true
		local h = world:run(DataService.save, session, false)
		world:advance(60)
		t.eq(h.results[1], false, "save returns false on persistent failure")
		t.eq(session.saveFailures, 1)
		t.truthy(#world.warnings > 0, "failure was logged")
		store.failAll = false
		local h2 = world:run(DataService.save, session, false)
		world:advance(5)
		t.eq(h2.results[1], true)
		t.eq(session.saveFailures, 0)
	end)

	t.test("a server whose lock went stale and was taken over cannot overwrite the newer session", function()
		local shared = {}
		local worldA = ServerWorld.new({ sharedStores = shared, jobId = "job-A" })
		local svcA = worldA:boot()
		local playerA = worldA:join(110)
		svcA.Sessions.get(playerA).data.coins = 100
		local store = worldA.stores[PROD]

		-- server A can no longer reach the store for longer than the lock timeout
		store.failAll = true
		worldA:advance(Game.Data.sessionLockTimeout + 60)
		store.failAll = false

		-- server B (another job) loads the stale-locked profile and plays on
		local worldB = ServerWorld.new({ sharedStores = shared, jobId = "job-B" })
		worldB:advance(Game.Data.sessionLockTimeout + 60)
		local svcB = worldB:boot()
		local playerB = worldB:join(110)
		local dataB = svcB.Sessions.get(playerB).data
		t.eq(dataB.coins, Game.Start.coins, "B took the stale profile (A never managed to save its coins)")
		dataB.coins = 5000
		worldB:leave(playerB)
		t.eq(store.data.Player_110.data.coins, 5000)

		-- server A recovers; its autosave must be refused and must not clobber B's progress
		worldA:advance(Game.Data.autosaveInterval + 5)
		t.eq(store.data.Player_110.data.coins, 5000, "newer session survives")
		t.truthy(worldA.kicked[110], "the stale session's player is removed instead of playing unsaved")
		worldA:assertNoErrors()
	end)

	t.test("BindToClose saves every player with a release and waits for leave-saves already in flight", function()
		local world, svc = boot()
		local store = world.stores[PROD]
		local p1 = world:join(111)
		local p2 = world:join(112)
		svc.Sessions.get(p1).data.coins = 11
		svc.Sessions.get(p2).data.coins = 22
		store.latency = 2
		world:beginLeave(p2) -- p2's leave-save is mid-flight when the server shuts down
		world:advance(0.5)
		local finished = world:shutdown(30)
		t.truthy(finished)
		t.eq(store.data.Player_111.data.coins, 11)
		t.eq(store.data.Player_111.lock, nil)
		t.eq(store.data.Player_112.data.coins, 22, "the in-flight leave-save was awaited, not abandoned")
		t.eq(store.data.Player_112.lock, nil)
		world:assertNoErrors()
	end)

	t.test("shutdown does not abandon a leave-save that was already running", function()
		local world, svc = boot()
		local store = world.stores[PROD]
		local player = world:join(116)
		svc.Sessions.get(player).data.coins = 616
		store.latency = 3
		world:beginLeave(player) -- leave-save pending; BindToClose has no sessions of its own to save
		world:advance(0.5)
		t.truthy(world:shutdown(30))
		t.eq(store.data.Player_116.data.coins, 616)
		t.eq(store.data.Player_116.lock, nil)
	end)

	t.test("the production store is never touched at boot and never probed", function()
		local world = boot({ studio = false })
		local store = world.stores[PROD]
		t.eq(#store.calls, 0, "no startup DataStore traffic in a live server")
		t.eq(store.commits, 0)
	end)

	t.test("Studio uses a separate store, and its startup probe is read-only", function()
		local world, svc = boot({ studio = true })
		t.eq(world.stores[PROD], nil, "Studio never opens the production store")
		local store = world.stores[STUDIO]
		t.truthy(store, "separate Studio store")
		t.eq(store.commits, 0, "the probe wrote nothing")
		local player = world:join(113)
		t.truthy(svc.Sessions.get(player).loaded)
		world:leave(player)
		t.eq(world.stores[PROD], nil)
		t.truthy(store.data.Player_113)
	end)

	t.test("Studio falls back to memory when the DataStore is unavailable; live servers never do", function()
		local studio, studioSvc = boot({ studio = true, storeFailAll = true })
		t.truthy(studioSvc.DataService.usingMemoryStore)
		local joined = studio:join(114)
		t.truthy(studioSvc.Sessions.get(joined).loaded, "playable in Studio without API access")

		local live, liveSvc = boot({ studio = false, storeFailAll = true })
		t.eq(liveSvc.DataService.usingMemoryStore, false)
		local p = live:join(115)
		live:advance(120)
		t.eq(liveSvc.Sessions.get(p), nil, "live servers refuse to run without a store")
		t.truthy(live.kicked[115])
	end)

	t.test("Studio failure injection makes loads fail safely and does nothing in live servers", function()
		local studio, studioSvc = boot({ studio = true })
		local seed = studio:join(117)
		studioSvc.Sessions.get(seed).data.coins = 1717
		studio:leave(seed)
		local store = studio.stores[STUDIO]
		local before = u:clone(store.data.Player_117)
		studioSvc.DataService.injectFailures(1000)
		local blocked = studio:join(117)
		studio:advance(120)
		t.truthy(studio.kicked[117], "player kicked, not given defaults")
		t.eq(studioSvc.Sessions.get(blocked), nil)
		t.deepEq(store.data.Player_117, before, "saved profile untouched by the injected outage")
		studioSvc.DataService.injectFailures(0)
		local back = studio:join(117)
		t.eq(studioSvc.Sessions.get(back).data.coins, 1717)

		local live, liveSvc = boot({ studio = false })
		liveSvc.DataService.injectFailures(1000)
		local p = live:join(118)
		t.truthy(liveSvc.Sessions.get(p).loaded, "injection is ignored outside Studio")
	end)

	t.test("the Studio failure drill can be armed from a workspace attribute before play", function()
		local world = ServerWorld.new({ studio = true })
		world.workspace:SetAttribute("ArmforgeFailStore", 1000)
		local svc = world:boot()
		local p = world:join(119)
		world:advance(120)
		t.truthy(world.kicked[119])
		t.eq(svc.Sessions.get(p), nil)
		t.eq(world.stores[STUDIO].commits, 0)

		local live = ServerWorld.new({ studio = false })
		live.workspace:SetAttribute("ArmforgeFailStore", 1000)
		local liveSvc = live:boot()
		t.truthy(liveSvc.Sessions.get(live:join(120)).loaded, "ignored in live servers")
	end)
end
