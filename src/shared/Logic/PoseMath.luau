--!strict
-- Evaluates procedural attack poses (Config/Animations) and derives timings shared by server and client.

local AnimConfig = require(script.Parent.Parent.Config.Animations)

local PoseMath = {}

export type Pose = AnimConfig.Pose
export type Move = AnimConfig.Move

local ZERO = Vector3.zero

local function ease(kind: string?, a: number): number
	if kind == "in" then
		return a ^ 2.2
	elseif kind == "out" then
		return 1 - (1 - a) ^ 2.2
	elseif kind == "linear" then
		return a
	end
	return a * a * (3 - 2 * a)
end

-- Pose of `move` at normalised time t (0..1); joints missing from a key count as zero.
function PoseMath.sample(move: Move, t: number): Pose
	local keys = move.keys
	t = math.clamp(t, 0, 1)
	local lo = keys[1]
	local hi = keys[#keys]
	for i = 1, #keys - 1 do
		if t >= keys[i].t and t <= keys[i + 1].t then
			lo, hi = keys[i], keys[i + 1]
			break
		end
	end
	local span = hi.t - lo.t
	local a = if span <= 1e-6 then 1 else ease(hi.ease, (t - lo.t) / span)
	local out: Pose = {}
	for joint, v in lo.pose do
		out[joint] = v:Lerp(hi.pose[joint] or ZERO, a)
	end
	for joint, v in hi.pose do
		if not out[joint] then
			out[joint] = ZERO:Lerp(v, a)
		end
	end
	return out
end

local SWAP = {
	RShoulder = "LShoulder",
	LShoulder = "RShoulder",
	RElbow = "LElbow",
	LElbow = "RElbow",
	RHip = "LHip",
	LHip = "RHip",
	RKnee = "LKnee",
	LKnee = "RKnee",
}

-- Left-handed version of a right-handed move: swap arms, negate yaw/roll and lateral offsets.
function PoseMath.mirrorPose(pose: Pose): Pose
	local out: Pose = {}
	for joint, v in pose do
		local name = (SWAP :: any)[joint] or joint
		if joint == "RootPos" then
			out[name] = Vector3.new(-v.X, v.Y, v.Z)
		else
			out[name] = Vector3.new(v.X, -v.Y, -v.Z)
		end
	end
	return out
end

function PoseMath.mirrorMove(move: Move, newName: string): Move
	local keys = {}
	for _, key in move.keys do
		table.insert(keys, { t = key.t, ease = key.ease, pose = PoseMath.mirrorPose(key.pose) })
	end
	local hand = if move.hand == "R" then "L" elseif move.hand == "L" then "R" else move.hand
	return {
		name = newName,
		duration = move.duration,
		contact = move.contact,
		keys = keys,
		hand = hand,
		shake = move.shake,
		hitstop = move.hitstop,
		power = move.power,
		trail = move.trail,
		finisher = move.finisher,
	}
end

local resolved: { [string]: Move }? = nil

-- All moves including generated mirrors, by name.
function PoseMath.moves(): { [string]: Move }
	if resolved then
		return resolved
	end
	local all: { [string]: Move } = {}
	for name, move in AnimConfig.Moves do
		all[name] = move
	end
	for mirrored, source in AnimConfig.MirrorOf do
		all[mirrored] = PoseMath.mirrorMove(AnimConfig.Moves[source], mirrored)
	end
	resolved = all
	return all
end

-- Move name played for the n-th strike (1-based) in a style's combo chain.
function PoseMath.moveForCombo(style: string, comboIndex: number): string
	local def = AnimConfig.Styles[style]
	local list = def.moves
	return list[((comboIndex - 1) % #list) + 1]
end

-- If the cooldown is shorter than the move, the animation is sped up so strikes never overlap.
function PoseMath.playSpeed(move: Move, cooldown: number): number
	return math.max(1, move.duration / math.max(0.05, cooldown))
end

-- Seconds from the start of the strike to the moment of impact.
function PoseMath.contactDelay(move: Move, cooldown: number): number
	return move.duration * move.contact / PoseMath.playSpeed(move, cooldown)
end

return PoseMath
