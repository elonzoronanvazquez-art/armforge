--!strict
-- Scoring for the four training mini-games and stat levelling. Mini-games run on a server-owned clock; these are
-- the pure parts (grade from timing/position, points -> stat levels).

local Config = script.Parent.Parent.Config
local Training = require(Config.Training)
local Formulas = require(script.Parent.Formulas)

local TrainingLogic = {}

export type Grade = "perfect" | "great" | "good" | "miss"

-- Triangular sweep 0 -> 1 -> 0 with the given period, starting at `start`.
function TrainingLogic.sweep(now: number, start: number, period: number): number
	local phase = ((now - start) / period) % 1
	return 1 - math.abs(phase * 2 - 1)
end

function TrainingLogic.gradeTiming(position: number): Grade
	local cfg = Training.Timing
	local d = math.abs(position - cfg.zoneCenter)
	if d <= cfg.perfect then
		return "perfect"
	elseif d <= cfg.great then
		return "great"
	elseif d <= cfg.good then
		return "good"
	end
	return "miss"
end

function TrainingLogic.gradeTapRate(rate: number): Grade
	local cfg = Training.Tap
	if rate >= cfg.perfectRate then
		return "perfect"
	elseif rate >= cfg.greatRate then
		return "great"
	elseif rate >= cfg.goodRate then
		return "good"
	end
	return "miss"
end

-- dx/dy: click offset from the target centre (normalised 0..1 of the panel); reaction: seconds since it appeared.
function TrainingLogic.gradeTarget(dx: number, dy: number, reaction: number): Grade
	local cfg = Training.Targets
	if reaction < cfg.minReaction or reaction > cfg.visible then
		return "miss"
	end
	local dist = math.sqrt(dx * dx + dy * dy)
	if dist > cfg.radius then
		return "miss"
	end
	if reaction <= cfg.perfect then
		return "perfect"
	elseif reaction <= cfg.great then
		return "great"
	end
	return "good"
end

-- Delta: seconds from the nearest beat.
function TrainingLogic.gradeBeat(delta: number): Grade
	local cfg = Training.Rhythm
	local d = math.abs(delta)
	if d <= cfg.perfect then
		return "perfect"
	elseif d <= cfg.great then
		return "great"
	elseif d <= cfg.good then
		return "good"
	end
	return "miss"
end

function TrainingLogic.pointsFor(grade: Grade): number
	return Training.GradePoints[grade]
end

-- Adds points to a stat and levels it up (respecting the cap for the player's level).
-- Returns {levelsGained, capped}. Excess points at the cap are discarded so stats cannot be banked past it.
function TrainingLogic.addPoints(data: any, stat: string, points: number): { levelsGained: number, capped: boolean }
	local entry = data.training[stat]
	local cap = Formulas.trainingLevelCap(stat, data.level)
	local gained = 0
	if entry.level >= cap then
		entry.points = 0
		return { levelsGained = 0, capped = true }
	end
	entry.points += points
	while entry.level < cap do
		local need = Formulas.trainingPointsToNext(entry.level)
		if entry.points < need then
			break
		end
		entry.points -= need
		entry.level += 1
		gained += 1
	end
	local capped = entry.level >= cap
	if capped then
		entry.points = 0
	end
	return { levelsGained = gained, capped = capped }
end

return TrainingLogic
