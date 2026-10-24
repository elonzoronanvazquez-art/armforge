--!strict
-- Who may use the developer commands. Pure, so it is tested. The rule is deliberately narrow:
--   * every player in Roblox Studio (a local test session is the developer's own),
--   * UserIds listed in Config/Game.Dev.allowedUserIds,
--   * the place's creator (a user-owned place), or the owner (rank 255) of a group-owned place, when Game.Dev.allowCreatorInLive is on.
-- Nobody else, ever. The server re-checks on every request; the client only uses the answer to decide whether to show the DEV button.

local DevAccess = {}

export type Facts = {
	studio: boolean,
	userId: number,
	creatorIsUser: boolean, -- the place belongs to a user (not a group)
	creatorId: number,
	groupRank: number, -- the player's rank in the owning group (0 when the place is user-owned or the lookup failed)
	allowedUserIds: { number },
	allowCreator: boolean,
}

function DevAccess.decide(f: Facts): boolean
	if f.studio then
		return true
	end
	if table.find(f.allowedUserIds, f.userId) then
		return true
	end
	if f.allowCreator and f.creatorId > 0 then
		if f.creatorIsUser then
			return f.userId == f.creatorId
		end
		return f.groupRank >= 255
	end
	return false
end

return DevAccess
