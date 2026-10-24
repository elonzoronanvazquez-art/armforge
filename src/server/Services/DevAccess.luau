--!strict
-- Authorization for the developer commands (Logic/DevAccess holds the rule). Group owner lookups yield, so the answer is computed once when a
-- player joins and cached; `allowed` itself never yields and is safe to call from the snapshot builder.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GroupService = game:GetService("GroupService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local Game = require(Shared.Config.Game)
local Logic = require(Shared.Logic.DevAccess)

local DevAccess = {}

local cache: { [Player]: boolean } = {}
local groupRank: { [Player]: number } = {}

-- (is the place user-owned, the owner's id); (false, 0) when the place is not published
local function creator(): (boolean, number)
	local ok, isUser, id = pcall(function()
		return game.CreatorType == Enum.CreatorType.User, game.CreatorId
	end)
	if ok and type(id) == "number" then
		return isUser :: boolean, id
	end
	return false, 0
end

local function decide(player: Player): boolean
	local creatorIsUser, creatorId = creator()
	return Logic.decide({
		studio = RunService:IsStudio(),
		userId = player.UserId,
		creatorIsUser = creatorIsUser,
		creatorId = creatorId,
		groupRank = groupRank[player] or 0,
		allowedUserIds = Game.Dev.allowedUserIds,
		allowCreator = Game.Dev.allowCreatorInLive,
	})
end

function DevAccess.allowed(player: Player): boolean
	local known = cache[player]
	if known == nil then
		known = decide(player)
		cache[player] = known
	end
	return known
end

local function prepare(player: Player)
	-- a group-owned place: look up the rank once (yields), then recompute
	local creatorIsUser, creatorId = creator()
	if not creatorIsUser and creatorId > 0 and Game.Dev.allowCreatorInLive and not RunService:IsStudio() then
		-- the owner of the owning group counts as rank 255
		local ok, info = pcall(function()
			return GroupService:GetGroupInfoAsync(creatorId)
		end)
		local owner = if ok and info and info.Owner then info.Owner.Id else 0
		groupRank[player] = if owner == player.UserId then 255 else 0
	end
	cache[player] = decide(player)
end

function DevAccess.start()
	for _, player in Players:GetPlayers() do
		task.spawn(prepare, player)
	end
	Players.PlayerAdded:Connect(function(player)
		task.spawn(prepare, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		cache[player] = nil
		groupRank[player] = nil
	end)
end

return DevAccess
