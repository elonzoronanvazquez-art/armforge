--!strict
-- Climbing routes: server-side judgement of a climb from sampled positions. A route is a vertical line (its truss) from `base` to `top`.
-- A climb begins when the player is at the foot of the line, must stay within `reach` of it while rising, may never jump ahead faster
-- than a person can climb (that is a teleport), and counts at the top only if it took at least the route's fastest honest time.
-- Positions are client-owned like every other proximity check in the game; this is a plausibility test, not anti-cheat.

local Mountain = require(script.Parent.Parent.Config.Mountain)

local Climb = {}

export type Route = { id: string, base: Vector3, top: Vector3, minSeconds: number }
export type Progress = { started: number, best: number }

-- How far along the route (0 foot .. 1 top) the position projects, and its distance from the route's axis.
function Climb.measure(route: Route, pos: Vector3): (number, number)
	local axis = route.top - route.base
	local len2 = axis:Dot(axis)
	local t = if len2 > 0 then math.clamp((pos - route.base):Dot(axis) / len2, 0, 1) else 0
	local nearest = route.base + axis * t
	return t, (pos - nearest).Magnitude
end

-- Advances one player's progress on one route. Returns the new progress (nil = not climbing) and an event: "begin" | "complete" | nil.
function Climb.step(progress: Progress?, route: Route, pos: Vector3, now: number): (Progress?, string?)
	local cfg = Mountain.Climb
	local t, dist = Climb.measure(route, pos)
	if not progress then
		if dist <= cfg.reach and t <= cfg.startFraction then
			return { started = now, best = t }, "begin"
		end
		return nil, nil
	end
	if dist > cfg.reach or now - progress.started > cfg.maxSeconds then
		-- fell off, wandered away, or took too long: start again from the foot
		if dist <= cfg.reach and t <= cfg.startFraction then
			return { started = now, best = t }, "begin"
		end
		return nil, nil
	end
	if t - progress.best > cfg.maxJump then
		return nil, nil -- not a climb
	end
	progress.best = math.max(progress.best, t)
	if progress.best >= cfg.doneFraction and now - progress.started >= route.minSeconds then
		return nil, "complete"
	end
	return progress, nil
end

return Climb
