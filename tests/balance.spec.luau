-- Balance simulation: a greedy "reasonable player" mines the best rock available, buys the next arm when it can,
-- upgrades otherwise, and we assert coarse pacing milestones (first upgrade quick, arms reachable, levels flowing).
-- Not a perfect model of a human; it guards against economy changes that make progression absurdly fast or slow.
return function(t, u)
	local Schema = u:load("Logic/DataSchema")
	local Equip = u:load("Logic/Equipment")
	local Combat = u:load("Logic/Combat")
	local Prog = u:load("Logic/Progression")
	local Formulas = u:load("Logic/Formulas")
	local Islands = u:load("Logic/Islands")
	local Arms = u:load("Config/Arms")
	local Rocks = u:load("Config/Rocks")
	local IslandCfg = u:load("Config/Islands")

	local TRAVEL = 3.5 -- seconds of walking/aiming between rocks

	local function dps(data, rock)
		local st = Combat.newState(data.arms.equipped)
		local s = Combat.stats(data, st, 0)
		local arm = Arms.Defs[s.armId]
		local expectedMult = 1 + s.critChance * (s.critMult - 1)
		local resist = math.clamp(rock.resistance * (1 - s.pierce), 0, 0.95)
		local famBonus = (arm.trait == "QuarryMaster" and rock.family == "stone") and 1.35 or 1
		local finisher = (arm.trait == "Finisher") and (1 + 0.45 / 3) or 1
		local sing = (arm.trait == "Singularity") and (1 + 2 / 4) or 1
		return s.power * expectedMult * (1 - resist) * famBonus * finisher * sing / s.cooldown
	end

	local function bestRock(data, island)
		local best, bestRate
		for _, field in IslandCfg.Defs[island].fields do
			for _, entry in field.rocks do
				local rock = Rocks.Defs[entry.rock]
				local rate_dps = dps(data, rock)
				local time = rock.maxHp / rate_dps + TRAVEL
				-- spawn weight: rare rocks are scarce, assume 1 in 6 mining actions can be a rare
				local rate = (rock.coins * Formulas.coinMultiplier(data, data.arms.equipped)) / time
				if rock.rare then
					rate *= 0.35
				end
				if not bestRate or rate > bestRate then
					best, bestRate = rock, rate
				end
			end
		end
		return best
	end

	local function run(maxSeconds, goalFn)
		local d = Schema.default()
		local clock = 0
		local log = {}
		local function mark(name)
			if not log[name] then
				log[name] = clock
			end
		end
		while clock < maxSeconds do
			-- pick island: the highest unlocked with rocks
			local island = "Forgeheart"
			for _, id in IslandCfg.Order do
				local def = IslandCfg.Defs[id]
				if not def.comingSoon and #def.fields > 0 then
					if d.islands.unlocked[id] or Islands.unlock(d, id).ok then
						island = id
					end
				end
			end
			local rock = bestRock(d, island)
			local rate = dps(d, rock)
			clock += rock.maxHp / rate + TRAVEL
			d.coins += math.floor(rock.coins * Formulas.coinMultiplier(d, d.arms.equipped))
			if rock.shards then
				d.shards += math.floor((rock.shards[1] + rock.shards[2]) / 2 * (rock.rare and 1 or 0))
			end
			local xp = Prog.addXp(d, math.floor(rock.xp * Formulas.xpMultiplier(d)))
			if d.level >= 2 then mark("level2") end
			if d.level >= 5 then mark("level5") end
			if d.level >= 12 then mark("level12") end
			if d.level >= 25 then mark("level25") end
			if d.level >= 30 then mark("level30") end

			-- shopping: buy the best affordable new arm, otherwise upgrade while cheap relative to wallet
			for _, id in Arms.Order do
				if Equip.purchaseBlocker(d, id) == nil then
					Equip.buyArm(d, id)
					Equip.equip(d, id)
					mark("buy" .. id)
				end
			end
			local eq = d.arms.equipped
			local cost = Formulas.upgradeCost(eq, d.arms.levels[eq] or 0)
			while cost and d.coins >= cost and cost <= d.coins * 0.6 do
				Equip.upgrade(d, eq)
				mark("firstUpgrade")
				cost = Formulas.upgradeCost(eq, d.arms.levels[eq] or 0)
			end
			if goalFn(d) then
				break
			end
		end
		return log, d, clock
	end

	t.test("first upgrade within 40 seconds of play, first level within 40", function()
		local log = run(600, function(d)
			return d.arms.levels.Starter >= 1 and d.level >= 2
		end)
		t.truthy(log.firstUpgrade and log.firstUpgrade <= 40, "first upgrade at " .. tostring(log.firstUpgrade))
		t.truthy(log.level2 and log.level2 <= 40, "level 2 at " .. tostring(log.level2))
	end)

	t.test("pacing milestones are in a sane window", function()
		local log, d, clock = run(3 * 3600, function(data)
			return data.level >= 25
		end)
		print("  [balance] milestones (seconds):")
		local names = {}
		for k in log do
			table.insert(names, k)
		end
		table.sort(names, function(a, b)
			return log[a] < log[b]
		end)
		for _, k in names do
			print(string.format("    %-16s %7.0fs (%.1f min)", k, log[k], log[k] / 60))
		end
		t.truthy(log.buyStonebreaker, "Stonebreaker reachable")
		t.truthy(log.buyStonebreaker >= 120 and log.buyStonebreaker <= 15 * 60, "Stonebreaker at " .. tostring(log.buyStonebreaker))
		t.truthy(log.level5 and log.level5 <= 12 * 60, "level 5 at " .. tostring(log.level5))
		t.truthy(log.buyAlloy and log.buyAlloy <= 50 * 60, "Alloy at " .. tostring(log.buyAlloy))
		t.truthy(log.level12 and log.level12 >= 8 * 60 and log.level12 <= 75 * 60, "level 12 at " .. tostring(log.level12))
	end)

	t.test("rebirth milestone is a substantial but reachable commitment", function()
		local log = run(8 * 3600, function(data)
			return data.level >= 30
		end)
		print(string.format("  [balance] level 30 at %.1f min", (log.level30 or 0) / 60))
		t.truthy(log.level30, "level 30 reachable within 8h of simulated play")
		t.truthy(log.level30 >= 40 * 60, "rebirth is not trivial: " .. tostring(log.level30))
	end)

	t.test("every arm is purchasable by its own gates in the simulated run (no dead arms)", function()
		local d = Schema.default()
		d.level = 40
		d.rebirths = 2
		d.coins = 1e9
		d.shards = 500
		for _, island in IslandCfg.Order do
			if not IslandCfg.Defs[island].comingSoon then
				d.islands.unlocked[island] = true
			end
		end
		for _, id in Arms.Order do
			if id ~= "Starter" then
				t.eq(Equip.purchaseBlocker(d, id), nil, id)
			end
		end
	end)

	t.test("each tier of arm clears its island's rocks faster than the previous tier would", function()
		local d = Schema.default()
		local function secondsPerRock(armId, rockId)
			d.arms.owned[armId] = true
			d.arms.levels[armId] = 0
			d.arms.equipped = armId
			return Rocks.Defs[rockId].maxHp / dps(d, Rocks.Defs[rockId])
		end
		t.truthy(secondsPerRock("Stonebreaker", "Ironvein") < secondsPerRock("Starter", "Ironvein"))
		t.truthy(secondsPerRock("Alloy", "Quartz") < secondsPerRock("Stonebreaker", "Quartz"))
		t.truthy(secondsPerRock("Crystal", "Amethyst") < secondsPerRock("Alloy", "Amethyst"))
		t.truthy(secondsPerRock("Magma", "MagmaCore") < secondsPerRock("Crystal", "MagmaCore"))
		t.truthy(secondsPerRock("Void", "Obsidian") < secondsPerRock("Magma", "Obsidian"))
		-- and a weak arm on a late island is miserable (gating works)
		t.truthy(secondsPerRock("Starter", "Quartz") > 60, "starter fists vs quartz takes a very long time")
	end)
end
