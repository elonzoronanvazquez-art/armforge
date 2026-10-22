--!strict
-- Keeps the character's visible arm set in sync with the authoritative equipment data, and exposes the
-- validated equip / buy / upgrade / cosmetic operations (all maths in shared/Logic/Equipment).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local Equipment = require(Shared.Logic.Equipment)
local Progression = require(Shared.Logic.Progression)
local ArmBuilder = require(Shared.Runtime.ArmBuilder)
local Sessions = require(script.Parent.Sessions)
local Sync = require(script.Parent.Sync)

local ArmService = {}

-- Rebuilds the arms on the player's current character from their data (REPLACES any previous set).
function ArmService.refresh(player: Player)
	local s = Sessions.get(player)
	local char = player.Character
	if not (s and s.data and char) then
		return
	end
	local armId: string = s.data.arms.equipped
	local recipe = Equipment.visualRecipe(s.data, armId)
	local model = ArmBuilder.attach(char, recipe)
	if model then
		char:SetAttribute("ArmId", armId)
	end
	s.combat.armId = armId
end

function ArmService.equip(player: Player, armId: string): Equipment.Result
	local s = Sessions.ready(player)
	if not s then
		return { ok = false, err = "not_ready" }
	end
	local result = Equipment.equip(s.data, armId)
	if result.ok then
		s.combat.combo = 0
		ArmService.refresh(player)
		Sync.mark(player)
	end
	return result
end

function ArmService.buy(player: Player, armId: string): Equipment.Result
	local s = Sessions.ready(player)
	if not s then
		return { ok = false, err = "not_ready" }
	end
	local result = Equipment.buyArm(s.data, armId)
	if result.ok then
		Sync.mark(player)
	end
	return result
end

function ArmService.upgrade(player: Player, armId: string): Equipment.Result
	local s = Sessions.ready(player)
	if not s then
		return { ok = false, err = "not_ready" }
	end
	local result = Equipment.upgrade(s.data, armId)
	if result.ok then
		Progression.markTutorial(s.data, "upgraded")
		if armId == s.data.arms.equipped then
			ArmService.refresh(player) -- visual tier may have changed
		end
		Sync.mark(player)
	end
	return result
end

function ArmService.buyCosmetic(player: Player, kind: string, id: string): Equipment.Result
	local s = Sessions.ready(player)
	if not s then
		return { ok = false, err = "not_ready" }
	end
	local result = Equipment.buyCosmetic(s.data, kind, id)
	if result.ok then
		Sync.mark(player)
	end
	return result
end

function ArmService.setCosmetic(player: Player, armId: string, kind: string, id: string): Equipment.Result
	local s = Sessions.ready(player)
	if not s then
		return { ok = false, err = "not_ready" }
	end
	local result = Equipment.setCosmetic(s.data, armId, kind, id)
	if result.ok then
		if armId == s.data.arms.equipped then
			ArmService.refresh(player)
		end
		Sync.mark(player)
	end
	return result
end

return ArmService
