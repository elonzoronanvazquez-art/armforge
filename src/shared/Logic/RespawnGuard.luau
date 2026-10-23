--!strict
-- Decides whether a rock may come back right now. A rock that respawns solid on top of a player would depenetrate
-- (shove) or trap them, so the server holds the respawn until nobody stands in the footprint. Pure: positions in,
-- yes/no out. Players are never moved, damaged or otherwise touched to make room.

local RespawnGuard = {}

-- vertical window around the footprint, in studs: a root part this far below the rock's base or above its top is
-- not overlapping it (the root part sits ~3 studs above the feet, so standing on the ground is well inside).
local BELOW = 8
local ABOVE = 6

-- base: the rock's ground position; radius/height: the footprint of the layout about to spawn;
-- clearance: extra studs around it so a player brushing the edge is not shoved by a growing collider.
function RespawnGuard.blocked(base: Vector3, radius: number, height: number, positions: { Vector3 }, clearance: number): boolean
	local limit = radius + clearance
	local limitSq = limit * limit
	for _, p in positions do
		local dx, dz = p.X - base.X, p.Z - base.Z
		if dx * dx + dz * dz <= limitSq and p.Y >= base.Y - BELOW and p.Y <= base.Y + height + ABOVE then
			return true
		end
	end
	return false
end

return RespawnGuard
