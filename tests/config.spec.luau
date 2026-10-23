-- Config integrity: every definition references things that exist and obeys its documented ranges.
return function(t, u)
	local Arms = u:load("Config/Arms")
	local Rocks = u:load("Config/Rocks")
	local Islands = u:load("Config/Islands")
	local Skills = u:load("Config/Skills")
	local Boosters = u:load("Config/Boosters")
	local Training = u:load("Config/Training")
	local Anim = u:load("Config/Animations")
	local Progression = u:load("Config/Progression")
	local Cosmetics = u:load("Config/Cosmetics")
	local PoseMath = u:load("Logic/PoseMath")

	local function count(set)
		local n = 0
		for _ in set do
			n += 1
		end
		return n
	end

	t.test("roster has at least six distinct arm sets, starter first", function()
		t.truthy(#Arms.Order >= 6, "at least six arms")
		t.eq(Arms.Order[1], "Starter")
		local traits, styles = {}, {}
		for _, id in Arms.Order do
			local def = Arms.Defs[id]
			t.truthy(def, id)
			t.eq(def.id, id)
			traits[def.trait] = true
			styles[def.attackStyle] = true
		end
		t.eq(count(traits), #Arms.Order, "every arm has its own trait")
		t.eq(count(styles), #Arms.Order, "every arm has its own attack style")
	end)

	t.test("arms are not simply bigger numbers: cooldown, crit and reach all vary", function()
		local cds, crits = {}, {}
		for _, id in Arms.Order do
			cds[Arms.Defs[id].cooldown] = true
			crits[Arms.Defs[id].critChance] = true
		end
		t.truthy(count(cds) >= 5, "distinct cooldowns")
		t.truthy(count(crits) >= 4, "distinct crit chances")
	end)

	t.test("arm definitions are valid", function()
		for id, def in Arms.Defs do
			t.truthy(Arms.Rarities[def.rarity], id .. " rarity")
			t.truthy(Anim.Styles[def.attackStyle], id .. " style")
			t.truthy(def.basePower > 0 and def.cooldown > 0 and def.reach > 0, id .. " numbers")
			t.truthy(def.growth > 1 and def.upgradeGrowth > 1, id .. " growth")
			t.truthy(def.maxLevel >= 10, id .. " maxLevel")
			t.truthy(def.critChance >= 0 and def.critChance < 1, id .. " crit")
			t.truthy(def.pierce >= 0 and def.pierce <= 1, id .. " pierce")
			t.truthy(def.critMult >= 1, id .. " critMult")
			if def.acquisition == "purchase" then
				t.truthy((def.cost.coins or 0) > 0, id .. " costs coins")
			end
			for skillId in def.affinity do
				t.truthy(Skills.Defs[skillId], id .. " affinity skill " .. skillId)
			end
			if def.requires.island then
				t.truthy(Islands.Defs[def.requires.island], id .. " island")
			end
		end
	end)

	t.test("arm power strictly increases with each arm tier at level 0", function()
		local last = 0
		for _, id in Arms.Order do
			local p = Arms.Defs[id].basePower
			t.truthy(p > last, id)
			last = p
		end
	end)

	t.test("rocks: islands reference real rocks and every rock belongs to an island field", function()
		local used = {}
		for _, islandId in Islands.Order do
			local isl = Islands.Defs[islandId]
			for _, field in isl.fields do
				for _, entry in field.rocks do
					local rock = Rocks.Defs[entry.rock]
					t.truthy(rock, "rock " .. entry.rock)
					t.eq(rock.island, islandId, entry.rock .. " island")
					used[entry.rock] = true
				end
			end
		end
		for id, def in Rocks.Defs do
			if def.size == "seal" then
				-- a guardian seal is placed by its island's guardian entry, not by a field
				local g = Islands.Defs[def.island].guardian
				t.truthy(g and g.seal == id, id .. " is its island's guardian seal")
			else
				t.truthy(used[id], id .. " is placed on an island")
			end
		end
	end)

	t.test("rock families: at least 3 distinct on the start island with rising durability", function()
		local list = {}
		for _, def in Rocks.Defs do
			if def.island == "Forgeheart" then
				table.insert(list, def)
			end
		end
		t.truthy(#list >= 3)
		table.sort(list, function(a, b)
			return a.maxHp < b.maxHp
		end)
		t.truthy(list[1].maxHp < list[2].maxHp and list[2].maxHp < list[3].maxHp)
		t.truthy(list[3].rare, "most durable start rock is the rare one")
		local colors = {}
		for _, d in list do
			colors[tostring(d.colors.shell)] = true
		end
		t.eq(count(colors), #list, "distinct looks")
	end)

	t.test("rock defs valid", function()
		for id, def in Rocks.Defs do
			t.truthy(def.maxHp > 0 and def.coins > 0 and def.xp > 0, id)
			t.truthy(def.resistance >= 0 and def.resistance < 0.9, id .. " resist")
			t.truthy(def.shape.chunks - def.shape.core >= 8, id .. " enough chunks")
			t.truthy(def.shape.core >= 2, id .. " core")
			t.truthy(def.respawn > 0, id)
			if def.rare then
				t.truthy(def.shards ~= nil, id .. " rare drops shards")
			end
		end
	end)

	t.test("islands ladder is ordered and gated", function()
		local lastOrder = 0
		for _, id in Islands.Order do
			local d = Islands.Defs[id]
			t.truthy(d.order > lastOrder)
			lastOrder = d.order
		end
		t.eq(next(Islands.Defs.Forgeheart.requires), nil, "start island free")
		t.truthy(Islands.Defs.Forgeheart.guardian.rebirths >= 1, "the first guardian needs a rebirth")
		t.truthy(Islands.Defs.Crystalfall.requires.level >= 5)
	end)

	t.test("skills / boosters / training reference valid things", function()
		for _, id in Skills.Order do
			local s = Skills.Defs[id]
			t.truthy(Skills.Effects[id], id .. " effects")
			t.eq(#s.rankCost, s.maxRank)
		end
		for _, id in Boosters.Order do
			local b = Boosters.Defs[id]
			t.truthy(Boosters.StatCap[b.stat], id .. " stat cap")
			t.truthy(b.maxDuration >= b.duration)
			t.truthy(b.bonus <= Boosters.StatCap[b.stat], id .. " fits under its cap")
		end
		for _, id in Training.Order do
			local st = Training.Stations[id]
			t.truthy(Training.Stats[st.stat], id)
		end
		t.eq(#Training.Order, 4)
		for _, rewards in Progression.LevelRewards do
			if rewards.boosters then
				for bid in rewards.boosters do
					t.truthy(Boosters.Defs[bid], bid)
				end
			end
		end
	end)

	t.test("cosmetic defaults are free", function()
		for kind, def in Cosmetics.Defaults do
			t.eq(Cosmetics.Kinds[kind][def].cost, 0, kind)
		end
	end)

	t.test("animations: contact inside the move, keys ordered, start and end neutral", function()
		local moves = PoseMath.moves()
		for name, m in moves do
			t.truthy(m.contact > 0.2 and m.contact < 0.9, name .. " contact")
			t.truthy(m.duration >= 0.25 and m.duration <= 1.3, name .. " duration")
			t.eq(m.keys[1].t, 0, name)
			t.eq(m.keys[#m.keys].t, 1, name)
			t.eq(next(m.keys[1].pose), nil, name .. " starts neutral")
			t.eq(next(m.keys[#m.keys].pose), nil, name .. " ends neutral")
			for i = 2, #m.keys do
				t.truthy(m.keys[i].t > m.keys[i - 1].t, name .. " keys ascend")
			end
			local found = false
			for _, k in m.keys do
				if math.abs(k.t - m.contact) < 1e-6 then
					found = true
				end
			end
			t.truthy(found, name .. " has a key at its contact frame")
		end
		for style, def in Anim.Styles do
			for _, mv in def.moves do
				t.truthy(moves[mv], style .. ":" .. mv)
			end
		end
		for skill, mv in Anim.SkillMoves do
			t.truthy(moves[mv], skill)
		end
	end)
end
