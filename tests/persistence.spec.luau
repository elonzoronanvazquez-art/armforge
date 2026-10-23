-- Pure persistence rules (Logic/Persistence + Logic/DataSchema) against an in-memory UpdateAsync store.
return function(t, u)
	local Persistence = u:load("Logic/Persistence")
	local DataSchema = u:load("Logic/DataSchema")
	local Game = u:load("Config/Game")

	local function fakeStore()
		local s = { data = {}, writes = 0 }
		function s.UpdateAsync(_, key, fn)
			local new = fn(Persistence.deepCopy(s.data[key]))
			if new == nil then
				return nil
			end
			s.writes += 1
			s.data[key] = Persistence.deepCopy(new)
			return Persistence.deepCopy(new)
		end
		return s
	end

	t.test("a record that is not a table is refused as corrupt and left untouched", function()
		local s = fakeStore()
		s.data.k = "garbage"
		local d, err = Persistence.load(s, "k", "jobA", 1000)
		t.eq(d, nil)
		t.eq(err, "corrupt")
		t.eq(s.data.k, "garbage")
		t.eq(s.writes, 0)
	end)

	t.test("a record whose data is not a table is refused as corrupt, not replaced by defaults", function()
		local s = fakeStore()
		s.data.k = { data = "oops", lock = nil }
		local d, err = Persistence.load(s, "k", "jobA", 1000)
		t.eq(d, nil)
		t.eq(err, "corrupt")
		t.eq(s.data.k.data, "oops")
	end)

	t.test("data written by a newer schema is refused so an old server cannot downgrade it", function()
		local s = fakeStore()
		s.data.k = { data = { version = Game.Data.schemaVersion + 1, coins = 5, futureField = true }, schema = Game.Data.schemaVersion + 1 }
		local d, err = Persistence.load(s, "k", "jobA", 1000)
		t.eq(d, nil)
		t.eq(err, "newer_schema")
		t.eq(s.data.k.data.futureField, true)
		t.eq(s.writes, 0)
	end)

	t.test("retry does not loop on refusals that cannot change", function()
		for _, err in { "corrupt", "newer_schema", "lost_lock", "locked" } do
			local calls = 0
			local ok, e = Persistence.retry(5, function() end, function()
				calls += 1
				return false, err
			end)
			t.eq(ok, false)
			t.eq(e, err)
			t.eq(calls, 1, err)
		end
	end)

	t.test("saves are fenced: a server that no longer holds the lock cannot write, even if the lock was released", function()
		local s = fakeStore()
		local dA = Persistence.load(s, "k", "jobA", 1000)
		-- A's lock goes stale; B takes over, plays, and leaves cleanly
		local dB = Persistence.load(s, "k", "jobB", 1000 + Game.Data.sessionLockTimeout + 1)
		dB.coins = 5000
		t.truthy(Persistence.save(s, "k", dB, "jobB", 1000 + Game.Data.sessionLockTimeout + 2, true))
		t.eq(s.data.k.lock, nil)
		dA.coins = 1
		local ok, err = Persistence.save(s, "k", dA, "jobA", 1000 + Game.Data.sessionLockTimeout + 3, false)
		t.eq(ok, false)
		t.eq(err, "lost_lock")
		t.eq(s.data.k.data.coins, 5000)
	end)

	t.test("saving without ever loading (no lock held) is refused", function()
		local s = fakeStore()
		local ok, err = Persistence.save(s, "k", DataSchema.default(), "jobA", 5, false)
		t.eq(ok, false)
		t.eq(err, "lost_lock")
		t.eq(s.data.k, nil)
	end)

	t.test("release frees only our lock and never rewrites the saved data", function()
		local s = fakeStore()
		local d = Persistence.load(s, "k", "jobA", 1000)
		d.coins = 321
		Persistence.save(s, "k", d, "jobA", 1001, false)
		local saved = Persistence.deepCopy(s.data.k.data)
		t.truthy(Persistence.release(s, "k", "jobA"))
		t.eq(s.data.k.lock, nil)
		t.deepEq(s.data.k.data, saved)

		-- a lock that belongs to someone else is left alone
		Persistence.load(s, "k", "jobB", 2000)
		t.truthy(Persistence.release(s, "k", "jobA"))
		t.eq(s.data.k.lock.jobId, "jobB")
		-- nothing stored: nothing to do
		t.truthy(Persistence.release(fakeStore(), "none", "jobA"))
	end)

	t.test("a store failure during release is reported, not swallowed", function()
		local failing = {
			UpdateAsync = function()
				error("boom")
			end,
		}
		local ok, err = Persistence.release(failing, "k", "jobA")
		t.eq(ok, false)
		t.truthy(string.find(err, "boom", 1, true))
	end)

	t.test("reconcile keeps valid progress and owned arm data intact", function()
		local raw = DataSchema.default()
		raw.coins = 1234
		raw.level = 9
		raw.xp = 77
		raw.rebirths = 1
		raw.arms.owned.Magma = true
		raw.arms.levels.Magma = 6
		raw.arms.equipped = "Magma"
		raw.training.power = { level = 4, points = 12 }
		raw.islands.unlocked.Crystalfall = true
		raw.stats.rocksDestroyed = 55
		local back = DataSchema.reconcile(Persistence.deepCopy(raw))
		t.eq(back.coins, 1234)
		t.eq(back.level, 9)
		t.eq(back.xp, 77)
		t.eq(back.rebirths, 1)
		t.eq(back.arms.owned.Magma, true)
		t.eq(back.arms.levels.Magma, 6)
		t.eq(back.arms.equipped, "Magma")
		t.eq(back.training.power.level, 4)
		t.eq(back.training.power.points, 12)
		t.eq(back.stats.rocksDestroyed, 55)
		t.eq(back.islands.unlocked.Crystalfall, true)
	end)

	t.test("reconcile drops unknown ids and garbage but never the starter arm or a valid equipped arm", function()
		local raw = DataSchema.default()
		raw.arms.owned.RemovedArm = true
		raw.arms.levels.RemovedArm = 9
		raw.arms.equipped = "RemovedArm"
		raw.coins = -50
		raw.level = "high"
		local back = DataSchema.reconcile(raw)
		t.eq(back.arms.owned.RemovedArm, nil)
		t.eq(back.arms.levels.RemovedArm, nil)
		t.eq(back.arms.equipped, "Starter")
		t.eq(back.arms.owned.Starter, true)
		t.eq(back.coins, 0)
		t.eq(back.level, 1)
	end)

	t.test("reconcile is idempotent", function()
		local raw = DataSchema.default()
		raw.coins = 99
		raw.arms.owned.Magma = true
		raw.arms.levels.Magma = 3
		local once = DataSchema.reconcile(Persistence.deepCopy(raw))
		local twice = DataSchema.reconcile(Persistence.deepCopy(once))
		t.deepEq(twice, once)
	end)

	t.test("a migration step runs for data from an older version and keeps its fields", function()
		local saved = DataSchema.Migrations[Game.Data.schemaVersion - 1]
		-- schemaVersion is 1 today: simulate a future bump by injecting a step for version 0 data
		DataSchema.Migrations[0] = function(raw)
			raw.coins = (raw.coins or 0) + 10
			return raw
		end
		local back = DataSchema.reconcile({ version = 0, coins = 5, arms = { owned = { Starter = true }, equipped = "Starter", levels = { Starter = 2 } } })
		DataSchema.Migrations[0] = nil
		t.eq(back.coins, 15)
		t.eq(back.arms.levels.Starter, 2)
		t.eq(back.version, Game.Data.schemaVersion)
		if saved then
			DataSchema.Migrations[Game.Data.schemaVersion - 1] = saved
		end
	end)
end
