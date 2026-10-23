-- Island guardians: the two-part gate (rebirths AND victory), per-island completion, schema v2 and creature/rock content rules.
return function(t, u)
	local Guardians = u:load("Logic/Guardians")
	local Islands = u:load("Logic/Islands")
	local Schema = u:load("Logic/DataSchema")
	local Progression = u:load("Logic/Progression")
	local Persistence = u:load("Logic/Persistence")
	local IslandCfg = u:load("Config/Islands")
	local Rocks = u:load("Config/Rocks")
	local Arms = u:load("Config/Arms")
	local Creatures = u:load("Config/Creatures")
	local SkillCfg = u:load("Config/Skills")
	local ProgressionCfg = u:load("Config/Progression")
	local Game = u:load("Config/Game")

	local function fresh()
		return Schema.default()
	end

	local function gate(d, id)
		return Guardians.gate(d, id, Islands.missing)
	end

	-- The two-part rule ------------------------------------------------------------------------------------------

	t.test("a rebirth alone never opens the next island", function()
		local d = fresh()
		d.level = 40
		d.coins = 1e12
		d.rebirths = 10
		t.deepEq(Islands.missing(d, "Crystalfall"), { "Defeat the guardian of Forgeheart Isle" })
		t.eq(Islands.unlock(d, "Crystalfall").err, "requirements")
		t.eq(d.islands.unlocked.Crystalfall, nil)
	end)

	t.test("a guardian victory alone never opens the next island", function()
		local d = fresh()
		d.level = 40
		d.guardians.defeated.Forgeheart = true -- as if recorded some other way
		t.deepEq(Islands.missing(d, "Crystalfall"), { "Rebirth 1" })
		t.eq(Islands.unlock(d, "Crystalfall").err, "requirements")
	end)

	t.test("both conditions plus the island's own level open it, and only that island", function()
		local d = fresh()
		d.rebirths = 1
		d.guardians.defeated.Forgeheart = true
		d.level = 11
		t.deepEq(Islands.missing(d, "Crystalfall"), { "Level 12" })
		d.level = 12
		t.deepEq(Islands.missing(d, "Crystalfall"), {})
		t.truthy(Islands.unlock(d, "Crystalfall").ok)
		-- Forgeheart's guardian does nothing for Emberfang
		d.level = 40
		d.coins = 1e12
		t.truthy(#Islands.missing(d, "Emberfang") >= 2)
		t.eq(Islands.unlock(d, "Emberfang").err, "requirements")
		t.eq(d.islands.unlocked.Emberfang, nil)
	end)

	t.test("every guardian island has its own record; beating one marks only that one", function()
		local d = fresh()
		d.rebirths = 3
		d.islands.unlocked.Crystalfall = true
		d.islands.unlocked.Emberfang = true
		local r = Guardians.recordDefeat(d, "Crystalfall")
		t.truthy(r.ok and r.first)
		t.eq(Guardians.defeated(d, "Crystalfall"), true)
		t.eq(Guardians.defeated(d, "Forgeheart"), false)
		t.eq(Guardians.defeated(d, "Emberfang"), false)
		t.eq(d.islands.completed.Crystalfall, true)
		t.eq(d.islands.completed.Forgeheart, nil)
		t.eq(d.stats.guardianVictories, 1)
	end)

	t.test("a guardian cannot be recorded without its rebirths or without access to the island", function()
		local d = fresh()
		local r = Guardians.recordDefeat(d, "Forgeheart")
		t.eq(r.ok, false)
		t.eq(Guardians.defeated(d, "Forgeheart"), false)
		d.rebirths = 1
		t.truthy(Guardians.recordDefeat(d, "Forgeheart").ok)
		local locked = Guardians.recordDefeat(d, "Crystalfall")
		t.eq(locked.ok, false, "no access to Crystalfall and not enough rebirths")
		d.rebirths = 5
		t.eq(Guardians.recordDefeat(d, "Crystalfall").ok, false, "still locked out of the island itself")
		t.eq(Guardians.recordDefeat(d, "Voidreach").err, "no_guardian")
		t.eq(Guardians.recordDefeat(d, "Nowhere").err, "no_guardian")
	end)

	t.test("repeat victories are not completion events", function()
		local d = fresh()
		d.rebirths = 1
		t.truthy(Guardians.recordDefeat(d, "Forgeheart").first)
		local again = Guardians.recordDefeat(d, "Forgeheart")
		t.truthy(again.ok)
		t.eq(again.first, false)
		t.eq(d.stats.guardianVictories, 1)
	end)

	t.test("eligibility is independent of level, coins or equipment", function()
		local d = fresh()
		d.level = 40
		d.coins = 1e15
		d.arms.owned.Void = true
		d.arms.equipped = "Void"
		t.eq(Guardians.canChallenge(d, "Forgeheart").ok, false)
		t.deepEq(Guardians.canChallenge(d, "Forgeheart").missing, { "Rebirth 1" })
		d.rebirths = 1
		t.eq(Guardians.canChallenge(d, "Forgeheart").ok, true)
	end)

	t.test("rebirth never defeats a guardian and never removes a victory or completion", function()
		local d = fresh()
		d.rebirths = 1
		t.truthy(Guardians.recordDefeat(d, "Forgeheart").ok)
		d.level = ProgressionCfg.Rebirth.minLevel
		d.coins = 1e9
		t.truthy(Progression.rebirth(d).ok)
		t.eq(d.rebirths, 2)
		t.eq(Guardians.defeated(d, "Forgeheart"), true)
		t.eq(d.islands.completed.Forgeheart, true)
		local other = fresh()
		other.level = ProgressionCfg.Rebirth.minLevel
		other.coins = 1e9
		t.truthy(Progression.rebirth(other).ok)
		t.eq(Guardians.defeated(other, "Forgeheart"), false, "a rebirth does not defeat anything")
	end)

	t.test("the four progression states the UI shows", function()
		local d = fresh()
		-- 1: rebirth requirement not met
		local g = gate(d, "Forgeheart")
		t.eq(g.state, "rebirth_needed")
		t.eq(g.nextState, "locked")
		-- 2: rebirth met, guardian undefeated
		d.rebirths = 1
		g = gate(d, "Forgeheart")
		t.eq(g.state, "ready")
		t.eq(g.defeated, false)
		-- 3: guardian defeated, other prerequisites (level) still missing
		Guardians.recordDefeat(d, "Forgeheart")
		d.level = 3
		g = gate(d, "Forgeheart")
		t.eq(g.state, "defeated")
		t.eq(g.nextState, "locked")
		t.deepEq(g.nextMissing, { "Level 12" })
		-- 4: everything satisfied, the next island can be unlocked
		d.level = 12
		g = gate(d, "Forgeheart")
		t.eq(g.nextState, "available")
		Islands.unlock(d, "Crystalfall")
		t.eq(gate(d, "Forgeheart").nextState, "unlocked")
	end)

	t.test("the last playable island's gate points at the teaser island, which stays closed", function()
		local d = fresh()
		d.rebirths = 9
		d.level = 40
		d.islands.unlocked.Crystalfall = true
		d.islands.unlocked.Emberfang = true
		Guardians.recordDefeat(d, "Emberfang")
		t.eq(Islands.unlock(d, "Voidreach").err, "coming_soon")
		t.eq(gate(d, "Voidreach").state, "no_guardian")
	end)

	-- Persistence and schema v2 -------------------------------------------------------------------------------------

	t.test("new profiles start with empty guardian state", function()
		local d = fresh()
		t.eq(d.version, Game.Data.schemaVersion)
		t.deepEq(d.guardians, { defeated = {} })
		t.deepEq(d.islands.completed, {})
		t.eq(d.stats.creaturesDefeated, 0)
		t.eq(d.stats.guardianVictories, 0)
	end)

	t.test("a v1 save migrates without losing arms, cosmetics, currency or progression", function()
		local old = fresh()
		old.version = 1
		old.guardians = nil
		old.islands.completed = nil
		old.stats.creaturesDefeated = nil
		old.stats.guardianVictories = nil
		old.coins = 4321
		old.level = 17
		old.arms.owned.Alloy = true
		old.arms.levels.Alloy = 5
		old.arms.equipped = "Alloy"
		old.cosmetics.owned["palette:Ember"] = true
		old.islands.unlocked.Crystalfall = true
		old.rebirths = 1
		local back = Schema.reconcile(Persistence.deepCopy(old))
		t.eq(back.version, Game.Data.schemaVersion)
		t.eq(back.coins, 4321)
		t.eq(back.level, 17)
		t.eq(back.arms.owned.Alloy, true)
		t.eq(back.arms.levels.Alloy, 5)
		t.eq(back.arms.equipped, "Alloy")
		t.eq(back.islands.unlocked.Crystalfall, true)
		t.eq(back.rebirths, 1)
		-- earned access is respected: Crystalfall was unlocked, so Forgeheart's guardian counts as done; nothing else does
		t.eq(back.guardians.defeated.Forgeheart, true)
		t.eq(back.islands.completed.Forgeheart, true)
		t.eq(back.guardians.defeated.Crystalfall, nil)
		t.eq(back.guardians.defeated.Emberfang, nil)
	end)

	t.test("a v1 save with only the start island gets no guardian credit", function()
		local old = fresh()
		old.version = 1
		old.guardians = nil
		local back = Schema.reconcile(old)
		t.deepEq(back.guardians.defeated, {})
		t.deepEq(back.islands.completed, {})
	end)

	t.test("guardian state round-trips through save and reload", function()
		local d = fresh()
		d.rebirths = 1
		Guardians.recordDefeat(d, "Forgeheart")
		local back = Schema.reconcile(Persistence.deepCopy(d))
		t.eq(back.guardians.defeated.Forgeheart, true)
		t.eq(back.islands.completed.Forgeheart, true)
		t.eq(back.stats.guardianVictories, 1)
		t.deepEq(Schema.reconcile(Persistence.deepCopy(back)), back, "idempotent")
	end)

	t.test("reconcile drops invented guardians and rebuilds the completion mirror from victories only", function()
		local d = fresh()
		d.guardians.defeated = { Forgeheart = true, Voidreach = true, Nowhere = true, Crystalfall = "yes" }
		d.islands.completed = { Emberfang = true, Forgeheart = true }
		local back = Schema.reconcile(d)
		t.eq(back.guardians.defeated.Forgeheart, true)
		t.eq(back.guardians.defeated.Voidreach, nil, "no guardian exists there yet")
		t.eq(back.guardians.defeated.Nowhere, nil)
		t.eq(back.guardians.defeated.Crystalfall, nil, "must be literally true")
		t.eq(back.islands.completed.Emberfang, nil, "completion without a victory is discarded")
		t.eq(back.islands.completed.Forgeheart, true)
	end)

	t.test("snapshot sends the guardian state to the owning client", function()
		local d = fresh()
		local snap = Schema.snapshot(d)
		t.truthy(snap.guardians)
		t.truthy(snap.islands.completed)
	end)

	-- Content rules ----------------------------------------------------------------------------------------------------

	local playable = {}
	for _, id in IslandCfg.Order do
		if IslandCfg.Defs[id].guardian then
			table.insert(playable, id)
		end
	end

	t.test("every playable island has a guardian with a seal, a boss creature and ascending rebirth gates", function()
		t.eq(#playable, 3)
		local lastRebirths = 0
		for _, id in playable do
			local g = IslandCfg.Defs[id].guardian
			local seal = Rocks.Defs[g.seal]
			local boss = Creatures.Defs[g.creature]
			t.truthy(seal and boss, id)
			t.eq(seal.size, "seal")
			t.eq(seal.encounter, g.creature)
			t.eq(seal.island, id)
			t.eq(boss.island, id)
			t.eq(boss.tier, "boss")
			t.truthy(g.rebirths > lastRebirths, "gates ascend")
			lastRebirths = g.rebirths
		end
		t.eq(IslandCfg.Defs.Voidreach.guardian, nil, "the teaser island has none yet")
		-- guardians are unique per island
		local seen = {}
		for _, id in playable do
			local c = IslandCfg.Defs[id].guardian.creature
			t.eq(seen[c], nil, "unique guardian")
			seen[c] = true
		end
	end)

	t.test("guardian bosses have phases, several readable attacks, an armor skill check and an exposed core", function()
		for _, id in playable do
			local boss = Creatures.Defs[IslandCfg.Defs[id].guardian.creature]
			t.truthy(#boss.attacks >= 3, boss.id .. " attacks")
			t.truthy(boss.phases and #boss.phases >= 2, boss.id .. " phases")
			t.truthy(boss.armor and #boss.armor.breakers >= 1, boss.id .. " armor")
			t.truthy(boss.core, boss.id .. " core")
			local interruptible, exposes = false, false
			for _, a in boss.attacks do
				interruptible = interruptible or a.interruptible == true
				exposes = exposes or a.exposesCore == true
				t.truthy(a.windup >= 1.0, `{boss.id}.{a.id} telegraphs for at least a second`)
				t.truthy(a.recover >= 1.4, `{boss.id}.{a.id} leaves a recovery window`)
			end
			t.truthy(interruptible, boss.id .. " has an interruptible attack")
			t.truthy(exposes, boss.id .. " has a core vulnerability window")
			t.truthy(boss.repeatMult and boss.repeatMult < 0.5, "repeat victories pay little")
		end
	end)

	t.test("every rock contains a real creature of its own island, matched to its size", function()
		for id, rock in Rocks.Defs do
			local c = Creatures.Defs[rock.encounter]
			t.truthy(c, id .. " creature")
			t.eq(c.island, rock.island, id .. " same island")
			if rock.size == "small" or rock.size == "medium" then
				t.eq(c.tier, "normal", id)
			elseif rock.size == "large" then
				t.eq(c.tier, "elite", id)
			else
				t.eq(rock.size, "seal", id)
				t.eq(c.tier, "boss", id)
			end
			t.truthy(rock.miningShare > 0 and rock.miningShare < 1, id .. " mining share")
		end
		for id, c in Creatures.Defs do
			local contained = 0
			for _, rock in Rocks.Defs do
				if rock.encounter == id then
					contained += 1
				end
			end
			t.eq(contained, 1, id .. " is released by exactly one rock")
		end
	end)

	t.test("each island offers small, medium and large rocks plus its seal, growing in size", function()
		for _, id in playable do
			local bySize = {}
			for _, field in IslandCfg.Defs[id].fields do
				for _, entry in field.rocks do
					bySize[Rocks.Defs[entry.rock].size] = Rocks.Defs[entry.rock]
				end
			end
			t.truthy(bySize.small and bySize.medium and bySize.large, id .. " has all three sizes")
			local seal = Rocks.Defs[IslandCfg.Defs[id].guardian.seal]
			local function volume(r)
				return r.shape.radius * r.shape.radius * r.shape.height
			end
			t.truthy(volume(bySize.small) < volume(bySize.medium) or bySize.small.shape.chunks < bySize.medium.shape.chunks, id .. " medium bigger than small")
			t.truthy(volume(bySize.large) > volume(bySize.medium), id .. " large bigger than medium")
			t.truthy(volume(seal) > volume(bySize.large), id .. " seal biggest")
			t.truthy(bySize.large.shape.chunks > bySize.small.shape.chunks, id .. " more fracture detail")
		end
	end)

	t.test("creature definitions are valid and fair", function()
		for id, c in Creatures.Defs do
			t.truthy(c.fight.seconds > 0 and c.fight.level >= 0 and c.speed > 0 and c.radius > 0 and c.emerge > 0, id)
			t.truthy(Arms.Defs[c.fight.arm] and c.fight.level <= Arms.Defs[c.fight.arm].maxLevel, id .. " reference loadout is real")
			t.truthy(#c.attacks >= 1, id .. " attacks")
			t.truthy(c.visual.glow ~= nil and c.visual.material ~= nil, id .. " visual")
			for _, a in c.attacks do
				t.truthy(a.windup >= 0.5, `{id}.{a.id} has a readable windup`)
				t.truthy(a.recover >= 0.8, `{id}.{a.id} has a recovery`)
				t.truthy(a.damage > 0 and a.damage < 60, `{id}.{a.id} damage bounded`)
				t.truthy(a.range > 0 and a.cooldown > 0, `{id}.{a.id}`)
				if a.kind == "circle" then
					t.truthy(a.radius, `{id}.{a.id} radius`)
				elseif a.kind == "cone" then
					t.truthy(a.length and a.halfAngle, `{id}.{a.id} cone`)
				else
					t.eq(a.kind, "line")
					t.truthy(a.length and a.width, `{id}.{a.id} line`)
				end
				t.truthy(#a.text > 10, `{id}.{a.id} describes its tell`)
			end
			if c.phases then
				local last = 1
				for _, p in c.phases do
					t.truthy(p.hpBelow < last and p.hpBelow > 0, id .. " phases descend")
					last = p.hpBelow
				end
			end
			if c.armor then
				t.truthy(c.armor.mult > 0 and c.armor.mult < 1 and c.armor.breakDuration >= 5, id .. " armor")
				for _, skill in c.armor.breakers do
					t.truthy(SkillCfg.Defs[skill], id .. " breaker is a real skill")
				end
			end
			for _, skill in c.interrupters or {} do
				t.truthy(SkillCfg.Defs[skill], id .. " interrupter is a real skill")
			end
		end
	end)

	t.test("the skill a creature demands can always be learned by its recommended level (no softlock)", function()
		for id, c in Creatures.Defs do
			local pointsAtLevel = c.recommended.level * ProgressionCfg.SkillPointsPerLevel
			local spent = 0
			for _, skill in c.recommended.skills do
				local def = SkillCfg.Defs[skill]
				t.truthy(def, id .. " " .. skill)
				t.truthy(def.unlockLevel <= c.recommended.level, `{id}: {skill} unlocks at level {def.unlockLevel}, creature recommends {c.recommended.level}`)
				spent += def.rankCost[1]
			end
			t.truthy(spent <= pointsAtLevel, `{id}: rank-1 of its skills costs {spent} of {pointsAtLevel} points`)
			-- anything near-immune to ordinary strikes must have a recommended skill that actually breaks it
			if c.armor and c.armor.mult <= 0.2 then
				local covered = false
				for _, skill in c.recommended.skills do
					if table.find(c.armor.breakers, skill) then
						covered = true
					end
				end
				t.truthy(covered, id .. ": near-immune armor has a documented, learnable breaker")
			end
			-- and a tough creature needs somewhere to attack even before that skill: the exposed core still takes full damage
			if c.armor and c.armor.mult <= 0.2 then
				t.truthy(c.core, id .. " has a core window as a second route")
			end
		end
	end)

	t.test("island creatures stay on their island and normal creatures never need a skill that unlocks later than level 12", function()
		for id, c in Creatures.Defs do
			t.truthy(IslandCfg.Defs[c.island], id)
			if c.tier == "normal" and c.island == "Forgeheart" then
				for _, skill in c.recommended.skills do
					t.truthy(SkillCfg.Defs[skill].unlockLevel <= 5, id .. " " .. skill)
				end
			end
		end
	end)
end
