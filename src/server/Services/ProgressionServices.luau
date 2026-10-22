--!strict
-- Smaller server services that wrap shared/Logic operations with world checks and client notifications:
--   Islands   unlock + travel (must be standing at a Skyport terminal)
--   Rebirth   prestige reset (must be standing at the Reforge Core)
--   Boosters  activation + ticking timers
--   Skills    learning with skill points

local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local IslandConfig = require(Shared.Config.Islands)
local IslandLogic = require(Shared.Logic.Islands)
local Progression = require(Shared.Logic.Progression)
local BoosterLogic = require(Shared.Logic.Boosters)
local SkillLogic = require(Shared.Logic.Skills)
local Sessions = require(script.Parent.Sessions)
local Sync = require(script.Parent.Sync)
local ArmService = require(script.Parent.ArmService)
local ProgressService = require(script.Parent.ProgressService)
local PlayerService = require(script.Parent.PlayerService)
local RockService = require(script.Parent.RockService)

local Services = {}

-- Is the player's character within `range` studs of any instance carrying `tag`?
local function nearTag(player: Player, tag: string, range: number): boolean
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return false
	end
	for _, inst in CollectionService:GetTagged(tag) do
		local pos: Vector3? = nil
		if inst:IsA("BasePart") then
			pos = inst.Position
		elseif inst:IsA("Model") then
			pos = inst:GetPivot().Position
		end
		if pos and (pos - hrp.Position).Magnitude <= range then
			return true
		end
	end
	return false
end
Services.nearTag = nearTag

-- Islands ---------------------------------------------------------------------------------------------------

function Services.unlockIsland(player: Player, islandId: string): { ok: boolean, err: string? }
	local s = Sessions.ready(player)
	if not s then
		return { ok = false, err = "not_ready" }
	end
	if not nearTag(player, "Skyport", 60) then
		return { ok = false, err = "not_at_skyport" }
	end
	local result = IslandLogic.unlock(s.data, islandId)
	if result.ok then
		Sync.mark(player)
		ProgressService.notify(player, "Toast", { text = `{IslandConfig.Defs[islandId].name} unlocked!`, kind = "good" })
	end
	return result
end

function Services.travel(player: Player, islandId: string): { ok: boolean, err: string? }
	local s = Sessions.ready(player)
	if not s then
		return { ok = false, err = "not_ready" }
	end
	if not nearTag(player, "Skyport", 60) then
		return { ok = false, err = "not_at_skyport" }
	end
	local check = IslandLogic.canTravel(s.data, islandId)
	if not check.ok then
		return check
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return { ok = false, err = "no_character" }
	end
	s.data.islands.current = islandId
	local def = IslandConfig.Defs[islandId]
	RockService.fxNear(hrp.Position, "Travel", { pos = hrp.Position, color = def.accent }, 80)
	hrp.CFrame = PlayerService.spawnCFrame(islandId)
	RockService.fxNear(hrp.Position, "Travel", { pos = hrp.Position, color = def.accent, arrive = true }, 80)
	Sync.mark(player)
	ProgressService.notify(player, "Island", { id = islandId, name = def.name, tagline = def.tagline })
	return { ok = true }
end

-- Rebirth ---------------------------------------------------------------------------------------------------

function Services.rebirth(player: Player): { ok: boolean, err: string?, rebirths: number? }
	local s = Sessions.ready(player)
	if not s then
		return { ok = false, err = "not_ready" }
	end
	if not nearTag(player, "RebirthAltar", 40) then
		return { ok = false, err = "not_at_altar" }
	end
	local result = Progression.rebirth(s.data)
	if result.ok then
		ArmService.refresh(player)
		ProgressService.updateLeaderstats(player)
		Sync.mark(player)
		ProgressService.notify(player, "Rebirth", { rebirths = s.data.rebirths })
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			RockService.fxNear(hrp.Position, "Rebirth", { pos = hrp.Position }, 150)
		end
	end
	return result
end

-- Boosters / skills --------------------------------------------------------------------------------------------

function Services.activateBooster(player: Player, id: string): BoosterLogic.Result
	local s = Sessions.ready(player)
	if not s then
		return { ok = false, err = "not_ready" }
	end
	local result = BoosterLogic.activate(s.data, id)
	if result.ok then
		Sync.mark(player)
	end
	return result
end

function Services.learnSkill(player: Player, id: string): { ok: boolean, err: string?, rank: number? }
	local s = Sessions.ready(player)
	if not s then
		return { ok = false, err = "not_ready" }
	end
	local result = SkillLogic.rankUp(s.data, id)
	if result.ok then
		Sync.mark(player)
	end
	return result
end

function Services.start()
	task.spawn(function()
		while true do
			task.wait(1)
			for player, s in Sessions.all() do
				if s.loaded and s.data and not s.leaving then
					if next(s.data.boosters.active) ~= nil then
						local expired = BoosterLogic.tick(s.data, 1)
						if #expired > 0 then
							ProgressService.notify(player, "Toast", { text = "A booster has run out.", kind = "info" })
							Sync.mark(player)
						end
					end
				end
			end
		end
	end)
end

return Services
