-- XP/levels, rebirth, islands, boosters, tutorial.
return function(t, u)
	local Schema = u:load("Logic/DataSchema")
	local Prog = u:load("Logic/Progression")
	local Formulas = u:load("Logic/Formulas")
	local Islands = u:load("Logic/Islands")
	local Boosters = u:load("Logic/Boosters")
	local PConfig = u:load("Config/Progression")
	local Skills = u:load("Config/Skills")
	local Training = u:load("Config/Training")

	local function fresh()
		return Schema.default()
	end

	t.test("xp curve is increasing and level 2 comes quickly", function()
		local last = 0
		for l = 1, PConfig.MaxLevel - 1 do
			local x = Formulas.xpToNext(l)
			t.truthy(x > last, "level " .. l)
			last = x
		end
		t.truthy(Formulas.xpToNext(1) <= 40, "first level in a handful of rocks")
	end)

	t.test("addXp below threshold does not level", function()
		local d = fresh()
		local r = Prog.addXp(d, 5)
		t.eq(r.levelsGained, 0)
		t.eq(d.xp, 5)
		t.eq(d.level, 1)
	end)

	t.test("exact threshold levels up and carries remainder", function()
		local d = fresh()
		local need = Formulas.xpToNext(1)
		local r = Prog.addXp(d, need + 3)
		t.eq(r.levelsGained, 1)
		t.eq(d.level, 2)
		t.eq(d.xp, 3)
		t.eq(d.skillPoints, 1)
		t.eq(d.coins, PConfig.LevelUpCoins * 2)
	end)

	t.test("big xp gains give multiple levels and every milestone reward", function()
		local d = fresh()
		local r = Prog.addXp(d, Formulas.totalXpForLevel(13) + 1)
		t.eq(d.level, 13)
		t.eq(r.levelsGained, 12)
		t.eq(d.skillPoints, 12)
		t.eq((d.boosters.inventory.CoinSurge or 0) >= 2, true, "level 2 and 12 coin surges")
		t.truthy(d.boosters.inventory.PowerSurge)
	end)

	t.test("max level caps xp", function()
		local d = fresh()
		Prog.addXp(d, Formulas.totalXpForLevel(PConfig.MaxLevel) * 3)
		t.eq(d.level, PConfig.MaxLevel)
		t.eq(d.xp, 0)
		local r = Prog.addXp(d, 1000)
		t.eq(r.levelsGained, 0)
	end)

	t.test("negative or zero xp is ignored", function()
		local d = fresh()
		Prog.addXp(d, -50)
		Prog.addXp(d, 0)
		t.eq(d.xp, 0)
	end)

	-- Rebirth -------------------------------------------------------------------------------------------
	t.test("rebirth requires level and coins", function()
		local d = fresh()
		t.eq(Prog.rebirthStatus(d).eligible, false)
		d.level = 30
		t.eq(Prog.rebirthStatus(d).eligible, false)
		d.coins = Formulas.rebirthCost(0)
		t.eq(Prog.rebirthStatus(d).eligible, true)
		d.level = 29
		t.eq(Prog.rebirthStatus(d).eligible, false)
	end)

	t.test("rebirth cost grows each time", function()
		t.truthy(Formulas.rebirthCost(1) > Formulas.rebirthCost(0))
		t.truthy(Formulas.rebirthCost(2) > Formulas.rebirthCost(1))
	end)

	t.test("rebirth resets exactly what the rules say and preserves the collection", function()
		local d = fresh()
		d.level = 33
		d.xp = 123
		d.coins = Formulas.rebirthCost(0) + 5000
		d.shards = 12
		d.skillPoints = 4
		d.skills.ranks.ChargedSmash = 3
		d.arms.owned.Stonebreaker = true
		d.arms.owned.Alloy = true
		d.arms.levels.Starter = 7
		d.arms.levels.Stonebreaker = 4
		d.arms.equipped = "Alloy"
		d.arms.levels.Alloy = 2
		d.cosmetics.owned["palette:Ember"] = true
		d.cosmetics.equipped.Alloy = { palette = "Ember" }
		d.training.power = { level = 20, points = 10 }
		d.islands.unlocked.Crystalfall = true
		d.boosters.inventory.CoinSurge = 2
		d.boosters.active.PowerSurge = 99
		d.tutorial.step = 5
		d.settings.sfx = 0.3

		local r = Prog.rebirth(d)
		t.truthy(r.ok)
		-- reset
		t.eq(d.level, 1)
		t.eq(d.xp, 0)
		t.eq(d.coins, 0)
		t.eq(d.skillPoints, 0)
		t.eq(d.skills.ranks.ChargedSmash, 0)
		t.eq(d.arms.levels.Starter, 0)
		t.eq(d.arms.levels.Stonebreaker, 0)
		t.eq(d.arms.levels.Alloy, 0)
		t.eq(d.training.power.level, 0)
		-- preserved
		t.eq(d.rebirths, 1)
		t.eq(d.shards, 12)
		t.truthy(d.arms.owned.Starter and d.arms.owned.Stonebreaker and d.arms.owned.Alloy, "collection intact")
		t.eq(d.arms.equipped, "Alloy")
		t.truthy(d.cosmetics.owned["palette:Ember"])
		t.eq(d.cosmetics.equipped.Alloy.palette, "Ember")
		t.truthy(d.islands.unlocked.Crystalfall)
		t.eq(d.boosters.active.PowerSurge, 99)
		t.truthy((d.boosters.inventory.CoinSurge or 0) >= 3, "rebirth reward booster added")
		t.eq(d.tutorial.step, 5)
		t.eq(d.settings.sfx, 0.3)
		t.near(Formulas.rebirthBonus(d.rebirths, "coins"), 0.25, 1e-9)
	end)

	t.test("failed rebirth changes nothing", function()
		local d = fresh()
		d.level = 10
		d.coins = 99
		local r = Prog.rebirth(d)
		t.eq(r.ok, false)
		t.eq(d.level, 10)
		t.eq(d.coins, 99)
		t.eq(d.rebirths, 0)
	end)

	t.test("rebirth reset rules are data driven", function()
		local cfg = u:clone(PConfig.Rebirth.resets)
		-- every reset flag documented in config is handled: flip one off and the field survives
		local d = fresh()
		d.level = 30
		d.coins = Formulas.rebirthCost(0)
		PConfig.Rebirth.resets.level = false
		Prog.rebirth(d)
		t.eq(d.level, 30, "level preserved when the rule is off")
		PConfig.Rebirth.resets.level = cfg.level
	end)

	t.test("rebirth multipliers apply to rewards", function()
		local d = fresh()
		d.rebirths = 2
		t.near(Formulas.coinMultiplier(d, "Starter"), 1.5, 1e-9)
		t.near(Formulas.xpMultiplier(d), 1.4, 1e-9)
	end)

	-- Islands -------------------------------------------------------------------------------------------
	t.test("start island is unlocked and always accessible", function()
		local d = fresh()
		t.truthy(Islands.canTravel(d, "Forgeheart").ok)
	end)

	t.test("later islands need level AND the previous guardian AND its rebirths, never just coins", function()
		local d = fresh()
		d.coins = 1e12
		t.eq(Islands.canTravel(d, "Crystalfall").err, "locked")
		t.eq(Islands.unlock(d, "Crystalfall").err, "requirements")
		d.level = 12
		t.eq(Islands.unlock(d, "Crystalfall").err, "requirements", "level alone is not enough any more")
		d.rebirths = 1
		d.guardians.defeated.Forgeheart = true
		t.truthy(Islands.unlock(d, "Crystalfall").ok)
		t.truthy(Islands.canTravel(d, "Crystalfall").ok)
		d.level = 25
		t.eq(Islands.unlock(d, "Emberfang").err, "requirements", "needs Crystalfall's guardian and two rebirths")
		d.guardians.defeated.Crystalfall = true
		t.deepEq(Islands.missing(d, "Emberfang"), { "Rebirth 2" })
		d.rebirths = 2
		t.truthy(Islands.unlock(d, "Emberfang").ok)
	end)

	t.test("unlock state survives; coming-soon islands cannot be entered", function()
		local d = fresh()
		d.level = 40
		d.rebirths = 5
		t.eq(Islands.unlock(d, "Voidreach").err, "coming_soon")
		t.eq(Islands.canTravel(d, "Voidreach").err, "coming_soon")
		t.eq(Islands.unknown, nil)
		t.eq(Islands.canTravel(d, "Nowhere").err, "unknown_island")
	end)

	-- Boosters ------------------------------------------------------------------------------------------
	t.test("booster needs inventory and consumes one", function()
		local d = fresh()
		t.eq(Boosters.activate(d, "CoinSurge").err, "none_left")
		Boosters.give(d, "CoinSurge", 2)
		local r = Boosters.activate(d, "CoinSurge")
		t.truthy(r.ok)
		t.eq(d.boosters.inventory.CoinSurge, 1)
		t.eq(d.boosters.active.CoinSurge, 600)
	end)

	t.test("re-activating extends but never beyond the maximum; refuses without consuming at max", function()
		local d = fresh()
		Boosters.give(d, "PowerSurge", 20)
		for _ = 1, 6 do
			Boosters.activate(d, "PowerSurge")
		end
		t.eq(d.boosters.active.PowerSurge, 1800)
		local before = d.boosters.inventory.PowerSurge
		t.eq(Boosters.activate(d, "PowerSurge").err, "max_duration")
		t.eq(d.boosters.inventory.PowerSurge, before)
	end)

	t.test("boosters expire on tick and stat bonuses add and cap", function()
		local d = fresh()
		d.boosters.active.PowerSurge = 10
		d.boosters.active.CoinSurge = 100
		t.near(Boosters.bonus(d, "power"), 0.25, 1e-9)
		t.near(Boosters.bonus(d, "coins"), 0.5, 1e-9)
		local expired = Boosters.tick(d, 11)
		t.deepEq(expired, { "PowerSurge" })
		t.eq(Boosters.bonus(d, "power"), 0)
		t.near(d.boosters.active.CoinSurge, 89, 1e-9)
		-- many sources of one stat are capped (inject two extra definitions' worth by config clone)
		local B = u:load("Config/Boosters")
		local saved = B.Defs.KnowledgeSurge.bonus
		B.Defs.KnowledgeSurge.bonus = 5
		d.boosters.active.KnowledgeSurge = 10
		t.near(Boosters.bonus(d, "xp"), B.StatCap.xp, 1e-9)
		B.Defs.KnowledgeSurge.bonus = saved
	end)

	t.test("boosters never multiply: two stats stay independent", function()
		local d = fresh()
		d.boosters.active.CoinSurge = 100
		d.boosters.active.KnowledgeSurge = 100
		t.near(Formulas.coinMultiplier(d, "Starter"), 1.5, 1e-9)
		t.near(Formulas.xpMultiplier(d), 1.5, 1e-9)
	end)

	-- Tutorial ------------------------------------------------------------------------------------------
	t.test("tutorial advances only through its flags, in order", function()
		local d = fresh()
		t.eq(d.tutorial.step, 1)
		t.truthy(Prog.markTutorial(d, "punched"))
		t.eq(d.tutorial.step, 2)
		t.eq(Prog.markTutorial(d, "trained"), false, "out-of-order flag does not skip")
		t.eq(d.tutorial.step, 2)
		Prog.markTutorial(d, "destroyed")
		Prog.markTutorial(d, "upgraded")
		t.eq(d.tutorial.step, 5, "stored 'trained' flag now satisfies its step")
		Prog.markTutorial(d, "finished")
		t.truthy(Prog.tutorialDone(d))
	end)
end
