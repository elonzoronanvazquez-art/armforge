-- Rock geometry + authoritative state machine.
local Vector3 = require("@lune/roblox").Vector3

return function(t, u)
	local Rocks = u:load("Config/Rocks")
	local Geometry = u:load("Logic/RockGeometry")
	local Sim = u:load("Logic/RockSim")
	local Rng = u:load("Util/Rng")

	local function newRock(id, seed)
		local def = Rocks.Defs[id]
		local layout = Geometry.generate(def, seed or 1)
		return Sim.new(1, def, layout), def, layout
	end

	t.test("layout is deterministic per seed and differs between seeds", function()
		local a = Geometry.generate(Rocks.Defs.Granite, 5)
		local b = Geometry.generate(Rocks.Defs.Granite, 5)
		local c = Geometry.generate(Rocks.Defs.Granite, 6)
		t.eq(#a.chunks, #b.chunks)
		for i = 1, #a.chunks do
			t.eq(a.chunks[i].pos, b.chunks[i].pos, "same seed")
		end
		local differs = false
		for i = 1, #a.chunks do
			if a.chunks[i].pos ~= c.chunks[i].pos then
				differs = true
			end
		end
		t.truthy(differs, "different seed gives a different rock")
	end)

	t.test("layout has the configured chunk counts and three layers", function()
		for id, def in Rocks.Defs do
			local l = Geometry.generate(def, 3)
			t.eq(#l.chunks, def.shape.chunks, id)
			local counts = { 0, 0, 0 }
			for _, c in l.chunks do
				counts[c.layer] += 1
			end
			t.eq(counts[3], def.shape.core, id .. " core")
			t.eq(counts[1] + counts[2], l.removable, id .. " removable")
			t.truthy(counts[1] >= 3 and counts[2] >= 2, id .. " layers populated")
			for _, c in l.chunks do
				t.truthy(c.size.X > 0 and c.size.Y > 0 and c.size.Z > 0, id .. " chunk size")
				t.truthy(c.pos.Y >= -0.01, id .. " chunk above ground")
				if c.cover then
					t.eq(l.chunks[c.cover].layer, 1, id .. " mid chunks are covered by shell chunks")
				end
			end
		end
	end)

	t.test("the first damaging hit strips material", function()
		local s = newRock("Granite")
		local r = Sim.apply(s, 1, 10, Vector3.new(0, 1, 0))
		t.eq(r.killed, false)
		t.truthy(#r.removed >= 1, "first hit strips a chunk")
		t.eq(s.stage, "SURFACE")
		t.eq(r.prevStage, "INTACT")
		t.truthy(r.stageChanged)
	end)

	t.test("full progression INTACT -> SURFACE -> CHIPPED -> FRACTURED -> COLLAPSE", function()
		local s, def = newRock("Ironvein")
		local seen = { s.stage }
		local last = s.stage
		local hits = 0
		while s.alive do
			Sim.apply(s, 1, def.maxHp / 20, Vector3.new(1, 0.3, 0))
			hits += 1
			if s.stage ~= last then
				table.insert(seen, s.stage)
				last = s.stage
			end
			t.truthy(hits < 100, "terminates")
		end
		t.deepEq(seen, { "INTACT", "SURFACE", "CHIPPED", "FRACTURED", "COLLAPSE" })
		t.eq(hits, 20)
	end)

	t.test("damage visibly changes geometry: removed chunk count rises monotonically with damage", function()
		local s, def = newRock("Granite")
		local prev = 0
		for _ = 1, 5 do
			Sim.apply(s, 1, def.maxHp / 8, Vector3.new(0, 1, 0))
			t.truthy(s.removedCount >= prev)
			prev = s.removedCount
		end
		t.truthy(s.removedCount >= s.layout.removable * 0.55, "most removable chunks gone by 5/8 damage")
		t.truthy(s.removedCount <= s.layout.removable - 1, "never strips everything before collapse")
	end)

	t.test("chips are localised: strikes from one side strip chunks facing that side first", function()
		local s = newRock("Granite", 4)
		local dir = Vector3.new(1, 0.2, 0).Unit
		local r = Sim.apply(s, 1, 5, dir)
		for _, idx in r.removed do
			t.truthy(s.layout.chunks[idx].dir:Dot(dir) > 0.3, "removed chunk faces the hit")
		end
	end)

	t.test("mid layer only becomes strippable after its shell cover is removed", function()
		local s, def = newRock("Ironvein", 2)
		for _ = 1, 30 do
			if not s.alive then
				break
			end
			local r = Sim.apply(s, 1, def.maxHp / 40, Vector3.new(0, 1, 0))
			for _, idx in r.removed do
				local c = s.layout.chunks[idx]
				if c.layer == 2 and c.cover then
					t.truthy(s.removed[c.cover], "cover removed before mid chunk")
				end
			end
		end
	end)

	t.test("final hit kills exactly once and collapses all remaining chunks", function()
		local s, def = newRock("Granite")
		Sim.apply(s, 1, def.maxHp - 1, nil)
		local r = Sim.apply(s, 1, 5, nil)
		t.eq(r.killed, true)
		t.eq(r.stage, "COLLAPSE")
		t.eq(#r.collapse + s.removedCount, #s.layout.chunks, "every chunk is either stripped or collapsed")
		t.eq(s.alive, false)
		local again = Sim.apply(s, 2, 999, nil)
		t.eq(again.ignored, true)
		t.eq(again.killed, false)
		t.eq(s.contributors[2], nil, "ignored hits do not become contributions")
	end)

	t.test("invalid damage is ignored", function()
		local s = newRock("Granite")
		for _, bad in { 0, -5, 0 / 0 } do
			local r = Sim.apply(s, 1, bad, nil)
			t.eq(r.ignored, true)
		end
		t.eq(s.hp, s.maxHp)
		t.eq(s.removedCount, 0)
	end)

	t.test("overkill is capped at remaining hp", function()
		local s = newRock("Granite")
		local r = Sim.apply(s, 1, 1e9, nil)
		t.eq(r.killed, true)
		t.eq(r.applied, 60)
		t.eq(s.contributors[1], 60)
	end)

	t.test("minChunks forces a visible bite (Charged Smash)", function()
		local s = newRock("Quartz")
		local r = Sim.apply(s, 1, 1, Vector3.new(0, 1, 0), 3)
		t.eq(#r.removed, 3)
	end)

	t.test("payout is paid once, only after death, and credits every contributor", function()
		local s, def = newRock("Ironvein")
		t.eq(Sim.payout(s, Rng.new(1)), nil, "alive rock pays nothing")
		Sim.apply(s, 10, def.maxHp * 0.5, nil)
		Sim.apply(s, 20, def.maxHp * 0.35, nil)
		Sim.apply(s, 30, def.maxHp * 0.15 + 5, nil)
		t.eq(s.alive, false)
		local rewards = Sim.payout(s, Rng.new(1))
		t.truthy(rewards)
		t.truthy(rewards[10] and rewards[20] and rewards[30])
		t.eq(rewards[10].coins, def.coins, "big contributor gets full reward")
		t.eq(rewards[20].coins, def.coins)
		t.truthy(rewards[30].killer)
		t.eq(rewards[30].coins, math.floor(def.coins * 1.1), "killer bonus on a full payout")
		t.eq(Sim.payout(s, Rng.new(1)), nil, "second payout attempt returns nothing")
	end)

	t.test("small contributors get a proportional share", function()
		local s, def = newRock("Ironvein")
		Sim.apply(s, 1, def.maxHp * 0.97, nil)
		Sim.apply(s, 2, def.maxHp * 0.02, nil)
		Sim.apply(s, 3, def.maxHp, nil)
		local r = Sim.payout(s, Rng.new(1))
		t.truthy(r[2].fraction < 1 and r[2].fraction > 0)
		t.truthy(r[2].coins < def.coins * 0.3)
	end)

	t.test("rare rocks drop shards within range", function()
		local s, def = newRock("Prism")
		Sim.apply(s, 1, def.maxHp, nil)
		local r = Sim.payout(s, Rng.new(9))
		t.truthy(r[1].shards >= def.shards[1] and r[1].shards <= def.shards[2])
	end)

	t.test("respawn restores a pristine rock and bumps the generation", function()
		local s, def = newRock("Granite")
		Sim.apply(s, 1, def.maxHp, nil)
		local gen = s.generation
		Sim.respawn(s)
		t.eq(s.hp, def.maxHp)
		t.eq(s.alive, true)
		t.eq(s.removedCount, 0)
		t.eq(s.generation, gen + 1)
		t.eq(s.paid, false)
		t.eq(next(s.contributors), nil)
		t.eq(s.stage, "INTACT")
	end)

	t.test("two players hitting the same rock cannot double-kill or double-pay", function()
		local s, def = newRock("Granite")
		local kills, pays = 0, 0
		for i = 1, 6 do
			local r = Sim.apply(s, (i % 2) + 1, def.maxHp / 4, nil)
			if r.killed then
				kills += 1
			end
		end
		if Sim.payout(s, Rng.new(2)) then
			pays += 1
		end
		if Sim.payout(s, Rng.new(2)) then
			pays += 1
		end
		t.eq(kills, 1)
		t.eq(pays, 1)
	end)

	t.test("stage thresholds", function()
		t.eq(Sim.stageFor(1), "INTACT")
		t.eq(Sim.stageFor(0.99), "SURFACE")
		t.eq(Sim.stageFor(0.6), "SURFACE")
		t.eq(Sim.stageFor(0.59), "CHIPPED")
		t.eq(Sim.stageFor(0.3), "CHIPPED")
		t.eq(Sim.stageFor(0.29), "FRACTURED")
	end)
end
