--!strict
-- Frostpeak Mountain mechanics: the climbing routes up the summit crown, the aerial tramway schedule and the slope limit that makes
-- the crown a real wall. Geometry is built by server/World/Islands/Crystalfall; the numbers live here so logic, services and the
-- builder agree. The reward boost these unlock ("Summit Momentum") is `momentum` on the island def (Config/Islands).

local Mountain = {}

export type Route = {
	id: string,
	name: string,
	angle: number, -- degrees around the summit (0 = +X, 90 = +Z)
	minSeconds: number, -- the fastest honest climb; anything quicker is a teleport
	blurb: string,
}

Mountain.Island = "Crystalfall"

Mountain.Routes = {
	{ id = "Frostline", name = "Frostline", angle = 120, minSeconds = 2.6, blurb = "The straight line up the crown. Ropes and pitons the whole way." },
	{ id = "Chimney", name = "The Chimney", angle = 200, minSeconds = 2.6, blurb = "A narrow crack on the west face. Out of the wind." },
	{ id = "Icefall", name = "Icefall", angle = 290, minSeconds = 2.6, blurb = "A frozen waterfall. Glassy, and the quickest way to feel the cold." },
} :: { Route }

Mountain.Climb = {
	reach = 3.8, -- studs from the route axis that still count as being on the route
	startFraction = 0.14, -- a climb begins when you are this low on the route
	doneFraction = 0.93, -- and counts when you get this high
	maxJump = 0.3, -- progress faster than this between two samples is a teleport
	maxSeconds = 150,
	cooldown = 20, -- seconds before the same route can pay momentum again
}

-- The tramway: two cabins swap ends. Both are docked at the same time, so you board the one at your station.
Mountain.Tram = {
	dock = 12, -- seconds both cabins wait at their stations
	travel = 16, -- seconds to cross
	capacity = 6, -- riders per cabin
	boardCutoff = 2, -- no boarding in the last seconds before departure
	stationRange = 18, -- how close to a station prompt a rider must be
	bearing = 49, -- degrees: the base station sits this far around the mountain, the cable runs straight up to the summit station
}

-- Characters on the mountain cannot walk up anything steeper than this, so the crown wall is climbed (routes) or flown (tram).
Mountain.SlopeLimit = 70
Mountain.Footprint = 150 -- studs from the summit within which the limit applies
Mountain.DefaultSlope = 89 -- Roblox default, restored elsewhere

return Mountain
