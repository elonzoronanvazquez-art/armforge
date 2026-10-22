-- Equipment, currency, cosmetics, training, persistence, schema, rate limiting.
return function(t, u)
	local Schema = u:load("Logic/DataSchema")
	local Equip = u:load("Logic/Equipment")
	local Formulas = u:load("Logic/Formulas")
	local Arms = u:load("Config/Arms")
	local Training = u:load("Config/Training")
	local TrainingLogic = u:load("Logic/TrainingLogic")
	local Persistence = u:load("Logic/Persistence")
	local RateLimiter = u:load("Logic/RateLimiter")
	local Game = u:load("Config/Game")

	local function fresh()
		return Schema.default()
	end

	local function countTrue(map)
		local n = 0
		for _, v in map do
			if v then
				n += 1
			end
		end
		return n
	end

	-- Equipment -----------------------------------------------------------------------------------------
	t.test("new players own and wield only the starter fists", function()
		local d = fresh()
		t.eq(d.arms.equipped, "Starter")
		t.eq(countTrue(d.arms.owned), 1)
	end)

	t.test("cannot equip an arm that is not owned", function()
		local d = fresh()
		local r = Equip.equip(d, "Void")
		t.eq(r.err, "not_owned")
		t.eq(d.arms.equipped, "Starter")
		t.eq(Equip.equip(d, "Nope").err, "not_owned")
	end)

	t.test("buying checks level, coins, shards, island and rebirths; charges exactly the price", function()
		local d = fresh()
		d.coins = 1000
		t.eq(Equip.buyArm(d, "Stonebreaker").err, "level")
		d.level = 3
		t.eq(Equip.buyArm(d, "Void").err, "level")
		d.coins = 899
		t.eq(Equip.buyArm(d, "Stonebreaker").err, "coins")
		t.eq(d.coins, 899, "failed purchase takes nothing")
		d.coins = 1000
		local r = Equip.buyArm(d, "Stonebreaker")
		t.truthy(r.ok)
		t.eq(d.coins, 100)
		t.truthy(d.arms.owned.Stonebreaker)
		t.eq(Equip.buyArm(d, "Stonebreaker").err, "already_owned")
		t.eq(d.coins, 100, "no double charge")

		local c = fresh()
		c.level = 20
		c.coins = 1e9
		t.eq(Equip.buyArm(c, "Crystal").err, "island")
		c.islands.unlocked.Crystalfall = true
		t.eq(Equip.buyArm(c, "Crystal").err, "shards")
		c.shards = 6
		t.truthy(Equip.buyArm(c, "Crystal").ok)
		t.eq(c.shards, 0)
		t.eq(c.coins, 1e9 - 28000)

		local v = fresh()
		v.level = 40
		v.coins = 1e12
		v.shards = 1000
		t.eq(Equip.buyArm(v, "Void").err, "rebirths")
		v.rebirths = 2
		t.truthy(Equip.buyArm(v, "Void").ok)
	end)

	t.test("equipping REPLACES the previous set: exactly one equipped, all ownership kept", function()
		local d = fresh()
		d.level = 20
		d.coins = 1e7
		Equip.buyArm(d, "Stonebreaker")
		Equip.buyArm(d, "Alloy")
		local seen = {}
		for _, id in { "Stonebreaker", "Alloy", "Starter", "Alloy" } do
			t.truthy(Equip.equip(d, id).ok)
			t.eq(type(d.arms.equipped), "string", "equipped slot is a single value")
			t.eq(d.arms.equipped, id)
			seen[id] = true
			t.eq(countTrue(d.arms.owned), 3, "owned count never changes while swapping")
		end
	end)

	t.test("upgrade charges the formula price and changes real power", function()
		local d = fresh()
		d.coins = 100
		local cost = Formulas.upgradeCost("Starter", 0)
		t.eq(cost, 18)
		local before = Formulas.armPower("Starter", d.arms.levels.Starter)
		local r = Equip.upgrade(d, "Starter")
		t.truthy(r.ok)
		t.eq(d.coins, 82)
		t.eq(d.arms.levels.Starter, 1)
		t.truthy(Formulas.armPower("Starter", 1) > before)
	end)

	t.test("upgrade is refused without coins, at max level, or for unowned arms", function()
		local d = fresh()
		d.coins = 5
		t.eq(Equip.upgrade(d, "Starter").err, "coins")
		t.eq(d.coins, 5)
		t.eq(Equip.upgrade(d, "Alloy").err, "not_owned")
		d.coins = 1e12
		d.arms.levels.Starter = Arms.Defs.Starter.maxLevel
		t.eq(Equip.upgrade(d, "Starter").err, "max_level")
		t.eq(Formulas.upgradeCost("Starter", Arms.Defs.Starter.maxLevel), nil)
	end)

	t.test("upgrade prices grow geometrically", function()
		for _, id in Arms.Order do
			local a = Formulas.upgradeCost(id, 0)
			local b = Formulas.upgradeCost(id, 1)
			t.truthy(b > a, id)
		end
	end)

	t.test("cosmetics are owned separately from stats and never change power", function()
		local d = fresh()
		d.coins = 5000
		local power = Formulas.armPower("Starter", 0)
		t.eq(Equip.setCosmetic(d, "Starter", "palette", "Ember").err, "cosmetic_locked")
		t.truthy(Equip.buyCosmetic(d, "palette", "Ember").ok)
		t.eq(d.coins, 4400)
		t.eq(Equip.buyCosmetic(d, "palette", "Ember").err, "already_owned")
		t.truthy(Equip.setCosmetic(d, "Starter", "palette", "Ember").ok)
		t.eq(Equip.selection(d, "Starter").palette, "Ember")
		t.eq(Equip.selection(d, "Starter").finish, "Standard")
		t.eq(Formulas.armPower("Starter", 0), power)
		t.eq(Equip.setCosmetic(d, "Alloy", "palette", "Default").err, "not_owned")
		t.eq(Equip.buyCosmetic(d, "palette", "Nope").err, "unknown_cosmetic")
		local recipe = Equip.visualRecipe(d, "Starter")
		t.eq(recipe.tier, 0)
		d.arms.levels.Starter = 8
		t.eq(Equip.visualRecipe(d, "Starter").tier, 2)
	end)

	-- Schema --------------------------------------------------------------------------------------------
	t.test("default data is complete", function()
		local d = fresh()
		t.eq(d.version, Game.Data.schemaVersion)
		for _, k in { "coins", "shards", "level", "xp", "arms", "cosmetics", "training", "skills", "boosters", "islands", "tutorial", "settings", "stats", "rebirths" } do
			t.truthy(d[k] ~= nil, k)
		end
	end)

	t.test("reconcile repairs hostile or corrupt data", function()
		local d = Schema.reconcile({
			coins = -50,
			shards = "lots",
			level = 9999,
			xp = 0 / 0,
			rebirths = 1e9,
			arms = {
				owned = { Void = true, FakeArm = true, Alloy = "yes" },
				levels = { Void = 9999, Starter = -5, Fake = 3 },
				equipped = "Alloy",
			},
			cosmetics = { owned = { ["palette:Ember"] = true, ["palette:Nope"] = true, junk = true }, equipped = { Void = { palette = "Royal" } } },
			boosters = { inventory = { CoinSurge = 5, Fake = 9 }, active = { PowerSurge = 99999 } },
			islands = { unlocked = { Emberfang = true, Voidreach = true, Zzz = true }, current = "Emberfang" },
			tutorial = { step = 99, flags = { punched = true } },
			training = { power = { level = 999, points = -3 } },
			skills = { ranks = { ChargedSmash = 99 } },
		})
		t.eq(d.coins, 0)
		t.eq(d.shards, 0)
		t.eq(d.level, 40)
		t.eq(d.xp, 0)
		t.eq(d.rebirths, 25)
		t.truthy(d.arms.owned.Void and d.arms.owned.Starter)
		t.eq(d.arms.owned.FakeArm, nil)
		t.eq(d.arms.owned.Alloy, nil)
		t.eq(d.arms.levels.Void, Arms.Defs.Void.maxLevel)
		t.eq(d.arms.levels.Starter, 0)
		t.eq(d.arms.equipped, "Starter", "equipped arm must be owned")
		t.truthy(d.cosmetics.owned["palette:Ember"])
		t.eq(d.cosmetics.owned["palette:Nope"], nil)
		t.eq(d.cosmetics.equipped.Void.palette, "Default", "unowned palette falls back")
		t.eq(d.boosters.inventory.CoinSurge, 5)
		t.eq(d.boosters.inventory.Fake, nil)
		t.eq(d.boosters.active.PowerSurge, 1800)
		t.truthy(d.islands.unlocked.Emberfang)
		t.eq(d.islands.unlocked.Voidreach, nil, "coming-soon islands cannot be saved as unlocked")
		t.eq(d.islands.unlocked.Zzz, nil)
		t.eq(d.tutorial.step, 6)
		t.eq(d.training.power.level, 40)
		t.eq(d.training.power.points, 0)
		t.eq(d.skills.ranks.ChargedSmash, 5)
	end)

	t.test("reconcile of non-table or nil returns defaults; round trip is stable", function()
		t.deepEq(Schema.reconcile(nil), fresh())
		t.deepEq(Schema.reconcile("garbage"), fresh())
		local d = fresh()
		d.coins = 123
		d.level = 7
		d.arms.owned.Alloy = true
		d.arms.levels.Alloy = 3
		d.arms.equipped = "Alloy"
		t.deepEq(Schema.reconcile(d), d)
	end)

	t.test("migrations run in order for old versions", function()
		local called = {}
		local saved = Game.Data.schemaVersion
		Game.Data.schemaVersion = 3
		Schema.Migrations[1] = function(raw)
			table.insert(called, 1)
			raw.coins = (raw.coins or 0) + 1
			return raw
		end
		Schema.Migrations[2] = function(raw)
			table.insert(called, 2)
			raw.coins = (raw.coins or 0) * 10
			return raw
		end
		local d = Schema.reconcile({ version = 1, coins = 4 })
		Game.Data.schemaVersion = saved
		Schema.Migrations[1] = nil
		Schema.Migrations[2] = nil
		t.deepEq(called, { 1, 2 })
		t.eq(d.coins, 50)
	end)

	-- Training ------------------------------------------------------------------------------------------
	t.test("training grades", function()
		local zone = Training.Timing.zoneCenter
		t.eq(TrainingLogic.gradeTiming(zone), "perfect")
		t.eq(TrainingLogic.gradeTiming(zone + 0.07), "great")
		t.eq(TrainingLogic.gradeTiming(zone - 0.12), "good")
		t.eq(TrainingLogic.gradeTiming(0.1), "miss")
		t.eq(TrainingLogic.gradeTapRate(7), "perfect")
		t.eq(TrainingLogic.gradeTapRate(1), "miss")
		t.eq(TrainingLogic.gradeTarget(0.01, 0.01, 0.3), "perfect")
		t.eq(TrainingLogic.gradeTarget(0.5, 0, 0.3), "miss")
		t.eq(TrainingLogic.gradeTarget(0, 0, 0.01), "miss", "inhumanly fast reaction")
		t.eq(TrainingLogic.gradeTarget(0, 0, 5), "miss", "too late")
		t.eq(TrainingLogic.gradeBeat(0.02), "perfect")
		t.eq(TrainingLogic.gradeBeat(-0.5), "miss")
	end)

	t.test("timing sweep is a triangle wave in 0..1", function()
		for i = 0, 40 do
			local p = TrainingLogic.sweep(i * 0.123, 0, 1.5)
			t.truthy(p >= 0 and p <= 1)
		end
		t.near(TrainingLogic.sweep(0, 0, 2), 0, 1e-9)
		t.near(TrainingLogic.sweep(1, 0, 2), 1, 1e-9)
		t.near(TrainingLogic.sweep(2, 0, 2), 0, 1e-9)
	end)

	t.test("training points level a stat up to the cap tied to player level", function()
		local d = fresh()
		d.level = 2
		local need = Formulas.trainingPointsToNext(0)
		local r = TrainingLogic.addPoints(d, "power", need + 3)
		t.eq(r.levelsGained, 1)
		t.eq(d.training.power.level, 1)
		t.eq(d.training.power.points, 3)
		local cap = Formulas.trainingLevelCap("power", 2)
		t.eq(cap, 5)
		local r2 = TrainingLogic.addPoints(d, "power", 1e6)
		t.eq(d.training.power.level, cap)
		t.truthy(r2.capped)
		t.eq(d.training.power.points, 0, "points beyond the cap are not banked")
		local r3 = TrainingLogic.addPoints(d, "power", 500)
		t.eq(r3.levelsGained, 0)
	end)

	t.test("training bonuses are bounded so mining stays relevant", function()
		for stat, info in Training.Stats do
			local max = info.perLevel * info.maxLevel
			t.truthy(max <= 0.65, stat .. " max bonus " .. max)
		end
	end)

	-- Persistence ---------------------------------------------------------------------------------------
	local function fakeStore()
		local store = { records = {}, failNext = 0, calls = 0 }
		function store.UpdateAsync(self, key, fn)
			self.calls += 1
			if self.failNext > 0 then
				self.failNext -= 1
				error("simulated DataStore outage")
			end
			local new = fn(u:clone(self.records[key]))
			if new == nil then
				return nil
			end
			self.records[key] = u:clone(new)
			return u:clone(new)
		end
		return store
	end

	t.test("new player loads defaults and takes the session lock", function()
		local s = fakeStore()
		local d, err, isNew = Persistence.load(s, "u1", "jobA", 1000)
		t.eq(err, nil)
		t.truthy(isNew)
		t.eq(d.coins, 0)
		t.eq(d.firstJoin, 1000)
		t.eq(s.records.u1.lock.jobId, "jobA")
	end)

	t.test("save then load in a new session returns the same data", function()
		local s = fakeStore()
		local d = Persistence.load(s, "u1", "jobA", 1000)
		d.coins = 777
		d.arms.owned.Alloy = true
		d.arms.levels.Alloy = 4
		d.arms.equipped = "Alloy"
		t.truthy(Persistence.save(s, "u1", d, "jobA", 1100, true))
		t.eq(s.records.u1.lock, nil, "released")
		local back, err = Persistence.load(s, "u1", "jobB", 1200)
		t.eq(err, nil)
		t.eq(back.coins, 777)
		t.eq(back.arms.equipped, "Alloy")
		t.eq(back.arms.levels.Alloy, 4)
	end)

	t.test("a second server cannot load while the first holds the lock, but can after it goes stale", function()
		local s = fakeStore()
		Persistence.load(s, "u1", "jobA", 1000)
		local d, err = Persistence.load(s, "u1", "jobB", 1100)
		t.eq(d, nil)
		t.eq(err, "locked")
		local d2, err2 = Persistence.load(s, "u1", "jobB", 1000 + Game.Data.sessionLockTimeout + 1)
		t.eq(err2, nil)
		t.truthy(d2)
	end)

	t.test("a server that lost its lock cannot overwrite the new owner's data", function()
		local s = fakeStore()
		local d = Persistence.load(s, "u1", "jobA", 1000)
		Persistence.load(s, "u1", "jobB", 1000 + Game.Data.sessionLockTimeout + 5)
		d.coins = 999999
		local ok, err = Persistence.save(s, "u1", d, "jobA", 1000 + Game.Data.sessionLockTimeout + 6, false)
		t.eq(ok, false)
		t.eq(err, "lost_lock")
		t.eq(s.records.u1.data, nil)
	end)

	t.test("DataStore failures retry with backoff and then succeed", function()
		local s = fakeStore()
		local d = Persistence.load(s, "u1", "jobA", 1000)
		d.coins = 5
		s.failNext = 2
		local waits = {}
		local ok = Persistence.retry(4, function(secs)
			table.insert(waits, secs)
		end, function()
			return Persistence.save(s, "u1", d, "jobA", 1001, false)
		end)
		t.truthy(ok)
		t.deepEq(waits, { 1, 2 })
		t.eq(s.records.u1.data.coins, 5)
	end)

	t.test("persistent failure gives up and reports the error; load errors are reported not thrown", function()
		local s = fakeStore()
		s.failNext = 99
		local ok, err = Persistence.retry(3, function() end, function()
			return Persistence.save(s, "u1", fresh(), "jobA", 1, false)
		end)
		t.eq(ok, false)
		t.truthy(string.find(err :: string, "error"))
		local d, lerr = Persistence.load(s, "u1", "jobA", 1)
		t.eq(d, nil)
		t.truthy(string.find(lerr :: string, "error"))
	end)

	t.test("corrupt stored data is repaired on load", function()
		local s = fakeStore()
		s.records.u1 = { data = { coins = "x", arms = { equipped = "Void" }, level = -4 } }
		local d = Persistence.load(s, "u1", "jobA", 5)
		t.eq(d.coins, 0)
		t.eq(d.arms.equipped, "Starter")
		t.eq(d.level, 1)
	end)

	-- Rate limiting -------------------------------------------------------------------------------------
	t.test("rate limiter allows a burst then throttles then refills", function()
		local rl = RateLimiter.new()
		local ok = 0
		for _ = 1, 20 do
			if rl:take("p:Punch", 5, 6, 0) then
				ok += 1
			end
		end
		t.eq(ok, 6, "burst only")
		t.eq(rl:take("p:Punch", 5, 6, 0.2), true, "refilled one token after 0.2s")
		t.eq(rl:take("p:Punch", 5, 6, 0.2), false)
		t.eq(rl:take("q:Punch", 5, 6, 0.2), true, "buckets are per key")
		rl:clear("p:")
		t.eq(rl.buckets["p:Punch"], nil)
	end)

	t.test("a spam of 1000 punches in one second is mostly rejected", function()
		local rl = RateLimiter.new()
		local rule = Game.RateLimits.Punch
		local ok = 0
		for i = 1, 1000 do
			if rl:take("p:Punch", rule.rate, rule.burst, i / 1000) then
				ok += 1
			end
		end
		t.truthy(ok <= rule.burst + rule.rate + 1, "accepted " .. ok)
	end)
end
