--!strict
-- Training stations. Each station runs a short mini-game on a SERVER-owned clock (workspace:GetServerTimeNow()); the
-- client only displays it and reports presses. Grading uses shared/Logic/TrainingLogic. Points are converted into
-- permanent stat levels (capped by player level) and a little XP when the session ends.
--
--   Timing   Power Press     press when the sweeping marker is in the zone
--   Tap      Speed Bag       tap as fast as possible for N seconds
--   Targets  Target Range    hit each target as it flashes (server places it, times it, and checks the click)
--   Rhythm   Endurance Rig   press on every beat

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local Net = require(Shared.Net)
local Game = require(Shared.Config.Game)
local Training = require(Shared.Config.Training)
local Formulas = require(Shared.Logic.Formulas)
local TrainingLogic = require(Shared.Logic.TrainingLogic)
local Progression = require(Shared.Logic.Progression)
local Validate = require(Shared.Util.Validate)
local RateLimiter = require(Shared.Logic.RateLimiter)
local Rng = require(Shared.Util.Rng)
local Sessions = require(script.Parent.Sessions)
local Sync = require(script.Parent.Sync)
local ProgressService = require(script.Parent.ProgressService)

local TrainingService = {}

local remotes: Net.Remotes
local limiter = RateLimiter.new()

type Run = {
	station: Training.Station,
	startT: number,
	endsT: number,
	points: number,
	reps: number,
	grades: { [string]: number },
	-- per-game state
	lastPress: number,
	taps: number,
	targetIndex: number,
	targetAppear: number,
	targetX: number,
	targetY: number,
	targetOpen: boolean,
	beatsDone: { [number]: boolean },
	active: boolean,
	token: number,
}

local function stationPart(player: Player, stationId: string): BasePart?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return nil
	end
	for _, inst in CollectionService:GetTagged("TrainStation") do
		if inst:IsA("BasePart") and inst:GetAttribute("StationId") == stationId then
			if (inst.Position - hrp.Position).Magnitude <= Training.StationRange then
				return inst
			end
		end
	end
	return nil
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function addGrade(run: Run, grade: string): number
	run.grades[grade] = (run.grades[grade] or 0) + 1
	local pts = TrainingLogic.pointsFor(grade :: any)
	run.points += pts
	return pts
end

local function finish(player: Player, session: Sessions.Session, run: Run, reason: string)
	if not run.active then
		return
	end
	run.active = false
	session.training = nil
	local data = session.data
	if not data then
		return
	end
	local stat = run.station.stat
	local rawPoints = run.points
	local mult = Formulas.trainingMultiplier(data)
	local points = math.floor(rawPoints * mult + 0.5)
	local result = TrainingLogic.addPoints(data, stat, points)
	local xp = math.floor(points * Training.XpPerPoint * Formulas.xpMultiplier(data))
	if rawPoints > 0 then
		data.stats.trainingSessions += 1
		Progression.markTutorial(data, "trained")
		if xp > 0 then
			ProgressService.addXp(player, xp)
		end
	end
	remotes.TrainingS:FireClient(player, "end", {
		station = run.station.id,
		stat = stat,
		points = points,
		xp = xp,
		levelsGained = result.levelsGained,
		level = data.training[stat].level,
		capped = result.capped,
		grades = run.grades,
		reason = reason,
	})
	Sync.mark(player)
end

local function cancel(player: Player, reason: string)
	local session = Sessions.get(player)
	if session and session.training then
		finish(player, session, session.training, reason)
	end
end

-- Mini-game drivers -------------------------------------------------------------------------------------------

local function runTargets(player: Player, session: Sessions.Session, run: Run)
	local cfg = Training.Targets
	local rng = Rng.new(math.floor(run.startT * 1000) + player.UserId)
	task.wait(1.0)
	for i = 1, cfg.reps do
		if not run.active then
			return
		end
		run.targetIndex = i
		run.targetX = rng:range(0.15, 0.85)
		run.targetY = rng:range(0.2, 0.8)
		run.targetAppear = serverNow()
		run.targetOpen = true
		remotes.TrainingS:FireClient(player, "target", { i = i, x = run.targetX, y = run.targetY, appear = run.targetAppear, visible = cfg.visible })
		local deadline = os.clock() + cfg.visible
		while run.active and run.targetOpen and os.clock() < deadline do
			task.wait(0.03)
		end
		if run.targetOpen then
			run.targetOpen = false
			run.reps += 1
			addGrade(run, "miss")
			remotes.TrainingS:FireClient(player, "grade", { i = i, grade = "miss", reps = run.reps })
		end
		task.wait(cfg.gap + rng:range(0, 0.35))
	end
	finish(player, session, run, "complete")
end

local function runTimer(player: Player, session: Sessions.Session, run: Run)
	while run.active and serverNow() < run.endsT do
		task.wait(0.1)
		local part = stationPart(player, run.station.id)
		if not part then
			finish(player, session, run, "left")
			return
		end
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then
			finish(player, session, run, "died")
			return
		end
	end
	if run.active then
		if run.station.game == "Tap" then
			local rate = run.taps / Training.Tap.duration
			local grade = TrainingLogic.gradeTapRate(rate)
			-- one grade stands in for a full set of reps so points are comparable between stations
			local pts = TrainingLogic.pointsFor(grade :: any) * Training.Timing.reps
			run.grades[grade] = 1
			run.points = pts
			remotes.TrainingS:FireClient(player, "grade", { grade = grade, rate = rate, taps = run.taps })
		elseif run.station.game == "Rhythm" then
			local missed = 0
			for k = 0, Training.Rhythm.beats - 1 do
				if not run.beatsDone[k] then
					missed += 1
				end
			end
			run.grades.miss = (run.grades.miss or 0) + missed
		end
		finish(player, session, run, "complete")
	end
end

-- Remote handler -------------------------------------------------------------------------------------------------

local function onTraining(player: Player, action: any, a: any, b: any, c: any)
	local act = Validate.id(action)
	if not act then
		return
	end
	if not limiter:take(`{player.UserId}:T`, Game.RateLimits.Training.rate, Game.RateLimits.Training.burst, os.clock()) then
		return
	end
	local session = Sessions.ready(player)
	if not session then
		return
	end
	local data = session.data

	if act == "start" then
		local id = Validate.id(a)
		local station = id and Training.Stations[id]
		if not station then
			return
		end
		if session.training then
			return
		end
		if data.level < station.unlockLevel then
			remotes.TrainingS:FireClient(player, "denied", { reason = `Reach level {station.unlockLevel} to use the {station.name}.` })
			return
		end
		if not stationPart(player, station.id) then
			remotes.TrainingS:FireClient(player, "denied", { reason = "Move closer to the station." })
			return
		end
		local now = serverNow()
		local run: Run = {
			station = station,
			startT = now + 1.5,
			endsT = 0,
			points = 0,
			reps = 0,
			grades = {},
			lastPress = -1e9,
			taps = 0,
			targetIndex = 0,
			targetAppear = 0,
			targetX = 0,
			targetY = 0,
			targetOpen = false,
			beatsDone = {},
			active = true,
			token = math.random(1, 1e9),
		}
		session.training = run
		local info: any = { station = station.id, game = station.game, startT = run.startT, stat = station.stat }
		if station.game == "Timing" then
			info.period = Training.Timing.period
			info.reps = Training.Timing.reps
			info.zone = Training.Timing.zoneCenter
			info.zoneGood = Training.Timing.good
			info.zonePerfect = Training.Timing.perfect
		elseif station.game == "Tap" then
			info.duration = Training.Tap.duration
			run.endsT = run.startT + Training.Tap.duration
		elseif station.game == "Targets" then
			info.reps = Training.Targets.reps
			info.radius = Training.Targets.radius
		elseif station.game == "Rhythm" then
			info.beats = Training.Rhythm.beats
			info.period = Training.Rhythm.period
			info.lead = Training.Rhythm.lead
			run.endsT = run.startT + Training.Rhythm.lead + Training.Rhythm.beats * Training.Rhythm.period + 0.6
		end
		if station.game == "Timing" then
			run.endsT = run.startT + Training.Timing.reps * Training.Timing.period * 1.2 + 30 -- safety net; ends on last rep
		end
		remotes.TrainingS:FireClient(player, "start", info)
		task.spawn(function()
			if station.game == "Targets" then
				runTargets(player, session, run)
			else
				runTimer(player, session, run)
			end
		end)
		return
	end

	local run = session.training :: Run?
	if not run or not run.active then
		return
	end

	if act == "stop" then
		finish(player, session, run, "stopped")
		return
	end

	local now = serverNow()
	local station = run.station
	if act == "press" and (station.game == "Timing" or station.game == "Rhythm") then
		local claimed = Validate.number(a)
		if claimed == nil then
			return
		end
		-- a client can only describe a moment in the recent past
		local t = math.clamp(claimed, now - 0.4, now)
		if t < run.startT then
			return
		end
		if station.game == "Timing" then
			local cfg = Training.Timing
			if run.reps >= cfg.reps or t - run.lastPress < cfg.minGap then
				return -- the set is complete (finish is only delayed for the result animation)
			end
			run.lastPress = t
			local pos = TrainingLogic.sweep(t, run.startT, cfg.period)
			local grade = TrainingLogic.gradeTiming(pos)
			run.reps += 1
			addGrade(run, grade)
			remotes.TrainingS:FireClient(player, "grade", { grade = grade, pos = pos, reps = run.reps })
			if run.reps >= cfg.reps then
				task.delay(0.6, finish, player, session, run, "complete")
			end
		else
			local cfg = Training.Rhythm
			local first = run.startT + cfg.lead
			local k = math.floor((t - first) / cfg.period + 0.5)
			if k < 0 or k >= cfg.beats or run.beatsDone[k] then
				return
			end
			local delta = t - (first + k * cfg.period)
			local grade = TrainingLogic.gradeBeat(delta)
			if grade == "miss" then
				return -- a stray press neither scores nor consumes the beat
			end
			run.beatsDone[k] = true
			run.reps += 1
			addGrade(run, grade)
			remotes.TrainingS:FireClient(player, "grade", { grade = grade, delta = delta, reps = run.reps, beat = k })
		end
	elseif act == "tap" and station.game == "Tap" then
		local cfg = Training.Tap
		if now < run.startT or now > run.endsT then
			return
		end
		if now - run.lastPress < cfg.minGap then
			return
		end
		run.lastPress = now
		run.taps += 1
		if run.taps % 4 == 0 then
			remotes.TrainingS:FireClient(player, "grade", { tap = run.taps })
		end
	elseif act == "hit" and station.game == "Targets" then
		if not run.targetOpen then
			return
		end
		local index = Validate.int(a)
		local nx, ny = Validate.number(b, -1, 2), Validate.number(c, -1, 2)
		if index ~= run.targetIndex or nx == nil or ny == nil then
			return
		end
		local t = now
		local reaction = t - run.targetAppear
		local grade = TrainingLogic.gradeTarget(nx - run.targetX, ny - run.targetY, reaction)
		run.targetOpen = false
		run.reps += 1
		addGrade(run, grade)
		remotes.TrainingS:FireClient(player, "grade", { i = index, grade = grade, reps = run.reps, reaction = reaction })
	end
end

function TrainingService.start()
	remotes = Net.server()
	remotes.Training.OnServerEvent:Connect(onTraining)
	Players.PlayerRemoving:Connect(function(player)
		cancel(player, "left")
		limiter:clear(`{player.UserId}:`)
	end)
end

function TrainingService.cancel(player: Player, reason: string)
	cancel(player, reason)
end

return TrainingService
