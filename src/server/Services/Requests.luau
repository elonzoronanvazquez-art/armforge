--!strict
-- The single RemoteFunction used for UI actions. Every action validates its arguments, is rate limited, and returns
-- {ok, err?}. Authoritative state changes happen in the services; after success the client gets a fresh snapshot.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local Net = require(Shared.Net)
local Game = require(Shared.Config.Game)
local Validate = require(Shared.Util.Validate)
local RateLimiter = require(Shared.Logic.RateLimiter)
local Progression = require(Shared.Logic.Progression)
local Sessions = require(script.Parent.Sessions)
local Sync = require(script.Parent.Sync)
local ArmService = require(script.Parent.ArmService)
local Services = require(script.Parent.ProgressionServices)

local Requests = {}

local limiter = RateLimiter.new()

type Handler = (Player, { [string]: any }) -> any

local SETTING_RANGES: { [string]: { number } } = {
	sfx = { 0, 1 },
	music = { 0, 1 },
	shake = { 0, 1 },
	uiScale = { 0.7, 1.4 },
}

local handlers: { [string]: Handler } = {
	Equip = function(player, args)
		local id = Validate.id(args.armId)
		if not id then
			return { ok = false, err = "bad_args" }
		end
		return ArmService.equip(player, id)
	end,
	BuyArm = function(player, args)
		local id = Validate.id(args.armId)
		if not id then
			return { ok = false, err = "bad_args" }
		end
		return ArmService.buy(player, id)
	end,
	UpgradeArm = function(player, args)
		local id = Validate.id(args.armId)
		if not id then
			return { ok = false, err = "bad_args" }
		end
		return ArmService.upgrade(player, id)
	end,
	BuyCosmetic = function(player, args)
		local kind, id = Validate.id(args.kind), Validate.id(args.id)
		if not (kind and id) then
			return { ok = false, err = "bad_args" }
		end
		return ArmService.buyCosmetic(player, kind, id)
	end,
	SetCosmetic = function(player, args)
		local armId, kind, id = Validate.id(args.armId), Validate.id(args.kind), Validate.id(args.id)
		if not (armId and kind and id) then
			return { ok = false, err = "bad_args" }
		end
		return ArmService.setCosmetic(player, armId, kind, id)
	end,
	LearnSkill = function(player, args)
		local id = Validate.id(args.skillId)
		if not id then
			return { ok = false, err = "bad_args" }
		end
		return Services.learnSkill(player, id)
	end,
	ActivateBooster = function(player, args)
		local id = Validate.id(args.id)
		if not id then
			return { ok = false, err = "bad_args" }
		end
		return Services.activateBooster(player, id)
	end,
	UnlockIsland = function(player, args)
		local id = Validate.id(args.islandId)
		if not id then
			return { ok = false, err = "bad_args" }
		end
		return Services.unlockIsland(player, id)
	end,
	Travel = function(player, args)
		local id = Validate.id(args.islandId)
		if not id then
			return { ok = false, err = "bad_args" }
		end
		return Services.travel(player, id)
	end,
	Rebirth = function(player)
		return Services.rebirth(player)
	end,
	SetSetting = function(player, args)
		local s = Sessions.ready(player)
		local key = Validate.string(args.key, 24)
		if not (s and key) then
			return { ok = false, err = "bad_args" }
		end
		local range = SETTING_RANGES[key]
		if range then
			local v = Validate.number(args.value, range[1], range[2])
			if v == nil then
				return { ok = false, err = "bad_args" }
			end
			s.data.settings[key] = v
		elseif key == "reduceFx" or key == "damageNumbers" then
			local v = Validate.bool(args.value)
			if v == nil then
				return { ok = false, err = "bad_args" }
			end
			s.data.settings[key] = v
		else
			return { ok = false, err = "bad_args" }
		end
		return { ok = true }
	end,
	TutorialAck = function(player)
		local s = Sessions.ready(player)
		if not s then
			return { ok = false, err = "not_ready" }
		end
		Progression.markTutorial(s.data, "finished")
		Sync.mark(player)
		return { ok = true }
	end,
}

function Requests.start()
	local remotes = Net.server()
	remotes.Request.OnServerInvoke = function(player: Player, action: any, args: any)
		local name = Validate.id(action)
		if not name then
			return { ok = false, err = "bad_request" }
		end
		local handler = handlers[name]
		if not handler then
			return { ok = false, err = "unknown_action" }
		end
		local rule = Game.RateLimits.Request
		if not limiter:take(`{player.UserId}:R`, rule.rate, rule.burst, os.clock()) then
			return { ok = false, err = "slow_down" }
		end
		local a = if type(args) == "table" then args else {}
		local ok, result = pcall(handler, player, a)
		if not ok then
			warn(`[ARMFORGE] request {name} failed: {tostring(result)}`)
			return { ok = false, err = "server_error" }
		end
		if type(result) == "table" and result.ok then
			Sync.now(player)
		end
		return result
	end
	Players.PlayerRemoving:Connect(function(player)
		limiter:clear(`{player.UserId}:`)
	end)
end

return Requests
