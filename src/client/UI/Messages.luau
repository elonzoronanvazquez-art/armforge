--!strict
-- Player-facing wording for server error codes, plus a helper that reports a request result (toast + sound).

local Notifications = require(script.Parent.Notifications)
local EffectsController = require(script.Parent.Parent.Controllers.EffectsController)

local Messages = {}

local TEXT: { [string]: string } = {
	coins = "Not enough coins.",
	shards = "Not enough Forge Shards.",
	level = "Your level is too low.",
	rebirths = "You need more rebirths.",
	island = "Unlock the required island first.",
	already_owned = "You already own that.",
	not_owned = "You don't own that yet.",
	max_level = "Already at maximum level.",
	max_rank = "Already at maximum rank.",
	skill_points = "Not enough skill points.",
	none_left = "You have none of those.",
	max_duration = "That booster is already at its maximum time.",
	locked = "That island is still locked.",
	requirements = "Requirements not met yet.",
	coming_soon = "Coming soon!",
	not_at_skyport = "Visit a Skyport terminal first.",
	not_at_altar = "Stand at the Reforge Core to rebirth.",
	not_eligible = "You don't meet the rebirth requirements yet.",
	cosmetic_locked = "Buy that style first.",
	slow_down = "Slow down a little.",
	network = "Connection problem, try again.",
	server_error = "Something went wrong. Try again.",
	not_for_sale = "That arm can't be bought.",
	bad_args = "Invalid request.",
}

function Messages.text(code: string?): string
	return TEXT[code or ""] or "That didn't work."
end

-- Reports the outcome of a Store.request. Returns result.ok.
function Messages.report(result: any, successText: string?, sound: string?): boolean
	if result and result.ok then
		if successText then
			Notifications.toast(successText, "good")
		end
		EffectsController.sound(sound or "Click", nil, 1, 1)
		return true
	end
	Notifications.toast(Messages.text(result and result.err), "bad")
	return false
end

return Messages
