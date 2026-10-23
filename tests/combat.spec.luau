-- Combat maths: stats derivation, traits, resistance, cooldowns, skills, animation timing.
return function(t, u)
	local Combat = u:load("Logic/Combat")
	local Schema = u:load("Logic/DataSchema")
	local Rng = u:load("Util/Rng")
	local Arms = u:load("Config/Arms")
	local Rocks = u:load("Config/Rocks")
	local Game = u:load("Config/Game")
	local PoseMath = u:load("Logic/PoseMath")
	local Skills = u:load("Logic/Skills")
	local Formulas = u:load("Logic/Formulas")

	local function player(arm, level)
		local d = Schema.default()
		d.arms.owned[arm] = true
		d.arms.equipped = arm
		d.arms.levels[arm] = level or 0
		return d
	end

	local function fixedRng(v)
		return { next = function()
			return v
		end }
	end

	t.test("starter stats match the config at level 0", function()
		local d = player("Starter")
		local s = Combat.stats(d, Combat.newState("Starter"), 0)
		t.near(s.power, 10, 1e-9)
		t.near(s.cooldown, 0.55, 1e-9)
		t.near(s.critChance, 0.05, 1e-9)
	end)

	t.test("upgrading an arm raises its power per the formula", function()
		local d = player("Starter", 5)
		local s = Combat.stats(d, Combat.newState("Starter"), 0)
		t.near(s.power, 10 * 1.14 ^ 5, 1e-6)
	end)

	t.test("training, rebirth and booster bonuses add before multiplying arm power", function()
		local d = player("Starter", 0)
		d.training.power.level = 10
		d.rebirths = 2
		d.boosters.active.PowerSurge = 100
		local s = Combat.stats(d, Combat.newState("Starter"), 0)
		t.near(s.power, 10 * (1 + 0.15 + 0.2 + 0.25), 1e-6)
	end)

	t.test("attack speed can never exceed the global cap", function()
		local d = player("Alloy", 0)
		d.training.haste.level = 30
		local st = Combat.newState("Alloy")
		st.buffs.overdrive = { untilT = 100, haste = 5, power = 0 }
		local s = Combat.stats(d, st, 1)
		t.truthy(s.cooldown >= Game.Combat.minCooldown - 1e-9)
		t.truthy(s.haste <= Game.Combat.maxHasteBonus + 1e-9)
	end)

	t.test("crit chance is capped", function()
		local d = player("Crystal", 0)
		d.training.precision.level = 30
		d.boosters.active.FocusSurge = 100
		local st = Combat.newState("Crystal")
		st.buffs.focus = { untilT = 100, bonus = 5 }
		local s = Combat.stats(d, st, 1)
		t.near(s.critChance, Game.Combat.maxCritChance, 1e-9)
	end)

	t.test("combo chains within the window and resets after", function()
		local st = Combat.newState("Starter")
		t.eq(Combat.registerStrike(st, 0, "Starter"), 1)
		t.eq(Combat.registerStrike(st, 0.5, "Starter"), 2)
		t.eq(Combat.registerStrike(st, 1.0, "Starter"), 3)
		t.eq(Combat.registerStrike(st, 5.0, "Starter"), 1, "reset after the window")
		t.eq(Combat.registerStrike(st, 5.3, "Starter"), 2)
		t.eq(Combat.registerStrike(st, 5.6, "Alloy"), 1, "switching arms breaks the combo")
	end)

	t.test("Starter finisher: every third punch is +45%", function()
		local d = player("Starter")
		local s = Combat.stats(d, Combat.newState("Starter"), 0)
		local rock = { family = "stone", resistance = 0 }
		local h1 = Combat.resolveHit(s, rock, 1, fixedRng(0.99))
		local h3 = Combat.resolveHit(s, rock, 3, fixedRng(0.99))
		t.eq(h1.damage, 10)
		t.eq(h3.damage, 15)
		t.truthy(h3.finisher and not h1.finisher)
	end)

	t.test("Stonebreaker beats stone, not ore", function()
		local d = player("Stonebreaker")
		local s = Combat.stats(d, Combat.newState("Stonebreaker"), 0)
		local stone = Combat.resolveHit(s, { family = "stone", resistance = 0 }, 1, fixedRng(0.99))
		local ore = Combat.resolveHit(s, { family = "ore", resistance = 0 }, 1, fixedRng(0.99))
		t.eq(stone.damage, 54)
		t.eq(ore.damage, 40)
		t.eq(stone.extraChunks, 1)
	end)

	t.test("Void Rend: 4th strike triples damage and pierces armour", function()
		local d = player("Void")
		local s = Combat.stats(d, Combat.newState("Void"), 0)
		local rock = { family = "magma", resistance = 0.35 }
		local normal = Combat.resolveHit(s, rock, 1, fixedRng(0.99))
		local rend = Combat.resolveHit(s, rock, 4, fixedRng(0.99))
		t.truthy(rend.rend and not normal.rend)
		t.truthy(rend.damage > normal.damage * 3, "extra pierce beyond the x3")
	end)

	t.test("Crystal crits resonate; Magma ignites", function()
		local c = Combat.stats(player("Crystal"), Combat.newState("Crystal"), 0)
		local hit = Combat.resolveHit(c, { family = "crystal", resistance = 0 }, 1, fixedRng(0))
		t.truthy(hit.crit and hit.splash)
		local noCrit = Combat.resolveHit(c, { family = "crystal", resistance = 0 }, 1, fixedRng(0.99))
		t.truthy(not noCrit.crit and not noCrit.splash)
		local m = Combat.stats(player("Magma"), Combat.newState("Magma"), 0)
		t.truthy(Combat.resolveHit(m, { family = "magma", resistance = 0 }, 1, fixedRng(0.99)).ignite)
	end)

	t.test("rock resistance reduces damage; pierce reduces resistance", function()
		local s = { armId = "Starter", power = 100, cooldown = 1, haste = 0, critChance = 0, critMult = 2, pierce = 0, reach = 8, trait = "None" }
		local rock = { family = "stone", resistance = 0.4 }
		t.eq(Combat.resolveHit(s, rock, 1, fixedRng(0.5)).damage, 60)
		s.pierce = 0.5
		t.eq(Combat.resolveHit(s, rock, 1, fixedRng(0.5)).damage, 80)
		t.eq(Combat.mitigate(1, 0.9, 0), 1, "damage is never below 1")
	end)

	t.test("crit multiplies damage", function()
		local s = { armId = "Starter", power = 100, cooldown = 1, haste = 0, critChance = 1, critMult = 2.5, pierce = 0, reach = 8, trait = "None" }
		local h = Combat.resolveHit(s, { family = "stone", resistance = 0 }, 1, fixedRng(0))
		t.eq(h.damage, 250)
		t.truthy(h.crit)
	end)

	t.test("Overclock stacks haste on consecutive hits then decays", function()
		local d = player("Alloy")
		local st = Combat.newState("Alloy")
		local base = Combat.stats(d, st, 0).cooldown
		for i = 1, 5 do
			Combat.registerStrike(st, i * 0.3, "Alloy")
		end
		local fast = Combat.stats(d, st, 1.6).cooldown
		t.truthy(fast < base * 0.85)
		local later = Combat.stats(d, st, 10).cooldown
		t.near(later, base, 1e-9)
	end)

	t.test("skills: learning, cooldown, overdrive buff then overheat", function()
		local d = player("Starter")
		d.level = 10
		d.skillPoints = 5
		local st = Combat.newState("Starter")
		t.eq(Combat.canUseSkill(d, st, "Overdrive", 0).err, "not_learned")
		t.truthy(Skills.rankUp(d, "Overdrive").ok)
		local ok = Combat.canUseSkill(d, st, "Overdrive", 0)
		t.truthy(ok.ok)
		local fx = Combat.startSkill(d, st, "Overdrive", 0)
		t.eq(Combat.canUseSkill(d, st, "Overdrive", 5).err, "cooldown")
		Combat.updateBuffs(st, 1)
		local boosted = Combat.stats(d, st, 1)
		t.truthy(boosted.cooldown < 0.55)
		Combat.updateBuffs(st, fx.duration + 1)
		local hot = Combat.stats(d, st, fx.duration + 1)
		t.truthy(hot.cooldown > 0.55, "overheat slows attacks right after")
		Combat.updateBuffs(st, fx.duration + fx.overheatDuration + 1)
		local cool = Combat.stats(d, st, fx.duration + fx.overheatDuration + 1)
		t.near(cool.cooldown, 0.55, 1e-9)
		t.truthy(Combat.canUseSkill(d, st, "Overdrive", 100).ok)
	end)

	t.test("skills need level and points", function()
		local d = player("Starter")
		d.skillPoints = 5
		t.eq(Skills.rankUp(d, "ChargedSmash").err, "level")
		d.level = 3
		d.skillPoints = 0
		t.eq(Skills.rankUp(d, "ChargedSmash").err, "skill_points")
		d.skillPoints = 1
		t.truthy(Skills.rankUp(d, "ChargedSmash").ok)
		t.eq(d.skillPoints, 0)
		t.eq(Skills.rank(d, "ChargedSmash"), 1)
	end)

	t.test("endurance training shortens cooldowns (capped)", function()
		local d = player("Starter")
		local base = Skills.cooldown(d, "ChargedSmash")
		d.training.endurance.level = 25
		t.near(Skills.cooldown(d, "ChargedSmash"), base * 0.75, 1e-9)
	end)

	t.test("arm affinity boosts the matching skill", function()
		local a = Skills.effect("ChargedSmash", 1, "Stonebreaker").damageMult
		local b = Skills.effect("ChargedSmash", 1, "Starter").damageMult
		t.near(a / b, 1.25, 1e-9)
	end)

	t.test("every arm's moves have contact times and the swing never overlaps the next strike", function()
		local moves = PoseMath.moves()
		for _, id in Arms.Order do
			local arm = Arms.Defs[id]
			local d = player(id, 0)
			local s = Combat.stats(d, Combat.newState(id), 0)
			for comboIndex = 1, 6 do
				local move = moves[PoseMath.moveForCombo(arm.attackStyle, comboIndex)]
				local delay = PoseMath.contactDelay(move, s.cooldown)
				t.truthy(delay > 0.05 and delay < 0.8, id .. " contact delay " .. delay)
				local speed = PoseMath.playSpeed(move, s.cooldown)
				t.truthy(move.duration / speed <= s.cooldown + 1e-6, id .. " animation fits its cooldown")
			end
		end
	end)

	t.test("mirrored moves swap hands and negate yaw", function()
		local moves = PoseMath.moves()
		t.eq(moves.JabL.hand, "L")
		local jabR = moves.JabR.keys[3].pose
		local jabL = moves.JabL.keys[3].pose
		t.eq(jabL.Waist.Y, -jabR.Waist.Y)
		t.eq(jabL.LShoulder.X, jabR.RShoulder.X)
	end)

	t.test("pose sampling interpolates and returns neutral at the ends", function()
		local m = PoseMath.moves().JabR
		local function neutral(pose)
			for _, v in pose do
				if v.Magnitude > 1e-6 then
					return false
				end
			end
			return true
		end
		t.truthy(neutral(PoseMath.sample(m, 0)))
		local mid = PoseMath.sample(m, m.contact)
		t.truthy(mid.RShoulder.X > 80)
		local half = PoseMath.sample(m, m.contact * 0.5)
		t.truthy(half.RShoulder.X > 0 and half.RShoulder.X < mid.RShoulder.X + 30)
		t.truthy(neutral(PoseMath.sample(m, 1)))
	end)

	t.test("combo chain cycles through the style's moves", function()
		t.eq(PoseMath.moveForCombo("Fists", 1), "JabR")
		t.eq(PoseMath.moveForCombo("Fists", 2), "JabL")
		t.eq(PoseMath.moveForCombo("Fists", 3), "CrossR")
		t.eq(PoseMath.moveForCombo("Fists", 4), "JabR")
	end)

	t.test("rng is deterministic", function()
		local a, b = Rng.new(42), Rng.new(42)
		for _ = 1, 20 do
			t.eq(a:next(), b:next())
		end
		local r = Rng.new(7)
		for _ = 1, 200 do
			local v = r:int(3, 6)
			t.truthy(v >= 3 and v <= 6)
		end
	end)

	t.test("peekStrike previews the chain without recording anything", function()
		local st = Combat.newState("Alloy")
		t.eq(Combat.peekStrike(st, 10, "Alloy"), 1)
		t.eq(Combat.peekStrike(st, 10, "Alloy"), 1, "peeking twice changes nothing")
		t.eq(st.combo, 0)
		t.eq(st.overclock, 0)
		Combat.registerStrike(st, 10, "Alloy")
		Combat.registerStrike(st, 10.4, "Alloy")
		t.eq(Combat.peekStrike(st, 10.8, "Alloy"), 3, "inside the window the next strike extends the chain")
		t.eq(Combat.peekStrike(st, 10.4 + Game.Combat.comboWindow + 0.01, "Alloy"), 1, "after the window it restarts")
		t.eq(Combat.peekStrike(st, 10.8, "Magma"), 1, "a different arm starts its own chain")
		t.eq(st.combo, 2)
		t.eq(st.overclock, 2)
	end)

	t.test("peekStrike always agrees with what registerStrike then returns", function()
		local st = Combat.newState("Alloy")
		local now = 0
		for step = 1, 30 do
			now += if step % 7 == 0 then 2 else 0.4
			local armId = if step % 11 == 0 then "Starter" else "Alloy"
			local peek = Combat.peekStrike(st, now, armId)
			t.eq(Combat.registerStrike(st, now, armId), peek, `step {step}`)
		end
	end)

	t.test("resetChain forgets combo, Overclock stacks and the chain timer", function()
		local st = Combat.newState("Alloy")
		Combat.registerStrike(st, 1, "Alloy")
		Combat.registerStrike(st, 1.3, "Alloy")
		Combat.resetChain(st)
		t.eq(st.combo, 0)
		t.eq(st.overclock, 0)
		t.eq(Combat.peekStrike(st, 1.4, "Alloy"), 1)
	end)
end
