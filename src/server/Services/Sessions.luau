--!strict
-- Per-player server session: the authoritative PlayerData plus transient combat / training state.
-- Everything else looks sessions up through here; nothing keeps its own per-player table of game state.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local Combat = require(Shared.Logic.Combat)
local Momentum = require(Shared.Logic.Momentum)

local Sessions = {}

export type Session = {
	player: Player,
	userId: number,
	data: any, -- nil until loaded
	loaded: boolean,
	combat: Combat.State,
	training: any?, -- active TrainingService session
	lastSync: number,
	dirty: boolean,
	leaving: boolean,
	joinedAt: number,
	saveFailures: number,
	flags: { [string]: any },
	momentum: Momentum.State?, -- Summit Momentum (Logic/Momentum), transient
}

local byPlayer: { [Player]: Session } = {}

function Sessions.create(player: Player): Session
	local session: Session = {
		player = player,
		userId = player.UserId,
		data = nil :: any,
		loaded = false,
		combat = Combat.newState("Starter"),
		training = nil,
		lastSync = 0,
		dirty = false,
		leaving = false,
		joinedAt = os.clock(),
		saveFailures = 0,
		flags = {},
		momentum = nil,
	}
	byPlayer[player] = session
	return session
end

function Sessions.get(player: Player): Session?
	return byPlayer[player]
end

-- The session, only if its data has been loaded (what every gameplay handler wants).
function Sessions.ready(player: Player): Session?
	local s = byPlayer[player]
	if s and s.loaded and s.data and not s.leaving then
		return s
	end
	return nil
end

function Sessions.remove(player: Player)
	byPlayer[player] = nil
end

function Sessions.all(): { [Player]: Session }
	return byPlayer
end

return Sessions
