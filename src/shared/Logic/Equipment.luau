--!strict
-- Arm ownership, equipping, upgrading and cosmetics. Operates on a PlayerData table and returns {ok, err}.
-- INVARIANT: data.arms.equipped is a single string, so a player can only ever have ONE active arm set.

local Config = script.Parent.Parent.Config
local Arms = require(Config.Arms)
local Cosmetics = require(Config.Cosmetics)
local Formulas = require(script.Parent.Formulas)

local Equipment = {}

export type Result = { ok: boolean, err: string?, cost: number?, level: number? }

local function fail(err: string): Result
	return { ok = false, err = err }
end

function Equipment.owns(data: any, armId: string): boolean
	return Arms.Defs[armId] ~= nil and data.arms.owned[armId] == true
end

function Equipment.level(data: any, armId: string): number
	return data.arms.levels[armId] or 0
end

-- Why an arm cannot be bought right now (nil if it can).
function Equipment.purchaseBlocker(data: any, armId: string): string?
	local def = Arms.Defs[armId]
	if not def then
		return "unknown_arm"
	end
	if data.arms.owned[armId] then
		return "already_owned"
	end
	if def.acquisition ~= "purchase" then
		return "not_for_sale"
	end
	local req = def.requires
	if req.level and data.level < req.level then
		return "level"
	end
	if req.rebirths and data.rebirths < req.rebirths then
		return "rebirths"
	end
	if req.island and not data.islands.unlocked[req.island] then
		return "island"
	end
	if (def.cost.coins or 0) > data.coins then
		return "coins"
	end
	if (def.cost.shards or 0) > data.shards then
		return "shards"
	end
	return nil
end

function Equipment.buyArm(data: any, armId: string): Result
	local blocker = Equipment.purchaseBlocker(data, armId)
	if blocker then
		return fail(blocker)
	end
	local def = Arms.Defs[armId]
	data.coins -= def.cost.coins or 0
	data.shards -= def.cost.shards or 0
	data.arms.owned[armId] = true
	data.arms.levels[armId] = 0
	return { ok = true }
end

-- Equips an owned arm set. Replaces whatever was equipped; ownership of the old set is untouched.
function Equipment.equip(data: any, armId: string): Result
	if not Equipment.owns(data, armId) then
		return fail("not_owned")
	end
	data.arms.equipped = armId
	return { ok = true }
end

function Equipment.upgrade(data: any, armId: string): Result
	if not Equipment.owns(data, armId) then
		return fail("not_owned")
	end
	local level = Equipment.level(data, armId)
	local cost = Formulas.upgradeCost(armId, level)
	if cost == nil then
		return fail("max_level")
	end
	if data.coins < cost then
		return fail("coins")
	end
	data.coins -= cost
	data.arms.levels[armId] = level + 1
	return { ok = true, cost = cost, level = level + 1 }
end

-- Cosmetics ------------------------------------------------------------------------------------------------

function Equipment.cosmeticKey(kind: string, id: string): string
	return `{kind}:{id}`
end

function Equipment.ownsCosmetic(data: any, kind: string, id: string): boolean
	local group = (Cosmetics.Kinds :: any)[kind]
	local entry = group and group[id]
	if not entry then
		return false
	end
	return entry.cost == 0 or data.cosmetics.owned[Equipment.cosmeticKey(kind, id)] == true
end

function Equipment.buyCosmetic(data: any, kind: string, id: string): Result
	local group = (Cosmetics.Kinds :: any)[kind]
	local entry = group and group[id]
	if not entry then
		return fail("unknown_cosmetic")
	end
	if Equipment.ownsCosmetic(data, kind, id) then
		return fail("already_owned")
	end
	if data.coins < entry.cost then
		return fail("coins")
	end
	data.coins -= entry.cost
	data.cosmetics.owned[Equipment.cosmeticKey(kind, id)] = true
	return { ok = true, cost = entry.cost }
end

function Equipment.selection(data: any, armId: string): { [string]: string }
	local sel = data.cosmetics.equipped[armId]
	local out = {}
	for _, kind in Cosmetics.KindOrder do
		out[kind] = (sel and sel[kind]) or (Cosmetics.Defaults :: any)[kind]
	end
	return out
end

function Equipment.setCosmetic(data: any, armId: string, kind: string, id: string): Result
	if not Equipment.owns(data, armId) then
		return fail("not_owned")
	end
	if not Equipment.ownsCosmetic(data, kind, id) then
		return fail("cosmetic_locked")
	end
	local sel = Equipment.selection(data, armId)
	sel[kind] = id
	data.cosmetics.equipped[armId] = sel
	return { ok = true }
end

-- Resolved visual recipe for an arm: palette colours + finish + trail colour + glow scale + upgrade tier.
function Equipment.visualRecipe(data: any, armId: string): any
	local def = Arms.Defs[armId]
	local sel = Equipment.selection(data, armId)
	local palette = Cosmetics.Palettes[sel.palette] or Cosmetics.Palettes.Default
	local finish = Cosmetics.Finishes[sel.finish] or Cosmetics.Finishes.Standard
	local trail = Cosmetics.Trails[sel.trail] or Cosmetics.Trails.Default
	local glow = Cosmetics.Glows[sel.glow] or Cosmetics.Glows.Normal
	local level = Equipment.level(data, armId)
	local tier = 0
	for _, threshold in Arms.VisualTierLevels do
		if level >= threshold then
			tier += 1
		end
	end
	return {
		armId = armId,
		primary = palette.primary or def.palette.primary,
		secondary = palette.secondary or def.palette.secondary,
		glow = palette.glow or def.palette.glow,
		trailColor = trail.color or palette.glow or def.palette.glow,
		material = finish.material or def.material,
		reflectance = finish.reflectance,
		glowScale = glow.scale,
		tier = tier,
	}
end

return Equipment
