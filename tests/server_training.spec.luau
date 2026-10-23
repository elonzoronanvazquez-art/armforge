-- TrainingService on the fake server: the server owns the clock, grading and rewards; clients only report presses.
local roblox = require("@lune/roblox")
local ServerWorld = require("./support/ServerWorld")

return function(t, u)
	local Training = u:load("Config/Training")
	local V = roblox.Vector3

	local function setup(level)
		local world = ServerWorld.new()
		local svc = world:boot()
		local player = world:join(501)
		local session = svc.Sessions.get(player)
		session.data.level = level or 10
		local station = world:addTagged("TrainStation", V.new(50, 0, 50), { StationId = "Power" })
		world:addTagged("TrainStation", V.new(50, 0, 50), { StationId = "Haste" })
		world:addTagged("TrainStation", V.new(50, 0, 50), { StationId = "Precision" })
		world:addTagged("TrainStation", V.new(50, 0, 50), { StationId = "Endurance" })
		world:placeCharacter(player, V.new(52, 3, 52))
		return world, svc, player, session, station
	end

	local function messages(world, player, kind)
		local out = {}
		for _, args in world:sent("TrainingS", player) do
			if args[1] == kind then
				table.insert(out, args[2])
			end
		end
		return out
	end

	local function start(world, player, station)
		world:fire("Training", player, "start", station)
	end

	t.test("a session starts only at the station, at the right level, once at a time", function()
		local world, svc, player, session = setup(1)
		start(world, player, "Power")
		t.eq(session.training, nil, "level too low")
		t.eq(#messages(world, player, "denied"), 1)

		session.data.level = 5
		world:placeCharacter(player, V.new(500, 3, 500))
		start(world, player, "Power")
		t.eq(session.training, nil, "too far from the station")
		t.eq(#messages(world, player, "denied"), 2)

		world:placeCharacter(player, V.new(52, 3, 52))
		start(world, player, "Power")
		t.truthy(session.training)
		local run = session.training
		start(world, player, "Haste")
		t.eq(session.training, run, "a second start while running is ignored")
		start(world, player, "Nonsense")
		t.eq(session.training, run)
		world:assertNoErrors()
	end)

	t.test("timing presses are graded on the server clock and capped at the number of reps", function()
		local world, svc, player, session = setup()
		start(world, player, "Power")
		local info = messages(world, player, "start")[1]
		world:advance(info.startT - world:serverNow() + 0.1)
		local cfg = Training.Timing
		for _ = 1, 40 do
			world:fire("Training", player, "press", world:serverNow())
			world:advance(cfg.minGap + 0.01)
		end
		world:advance(3)
		local finished = messages(world, player, "end")
		t.eq(#finished, 1)
		t.eq(finished[1].reason, "complete")
		local total = 0
		for _, n in finished[1].grades do
			total += n
		end
		t.eq(total, cfg.reps, "forty presses still grade exactly one set")
		t.eq(session.training, nil)
		t.eq(session.data.stats.trainingSessions, 1)
		world:assertNoErrors()
	end)

	t.test("presses before the start time, in the future, or too fast are ignored", function()
		local world, svc, player, session = setup()
		start(world, player, "Power")
		local info = messages(world, player, "start")[1]
		world:fire("Training", player, "press", world:serverNow()) -- before the countdown ends
		t.eq(session.training.reps, 0)
		world:advance(info.startT - world:serverNow() + 0.1)
		world:fire("Training", player, "press", world:serverNow() + 100) -- claims a future moment: clamped to now
		t.eq(session.training.reps, 1)
		world:fire("Training", player, "press", world:serverNow()) -- inside minGap
		t.eq(session.training.reps, 1)
		world:fire("Training", player, "press", "soon")
		world:fire("Training", player, "press", 0 / 0)
		t.eq(session.training.reps, 1)
		world:assertNoErrors()
	end)

	t.test("speed-bag taps are limited by the minimum gap however hard the client spams", function()
		local world, svc, player, session = setup()
		start(world, player, "Haste")
		local info = messages(world, player, "start")[1]
		world:advance(info.startT - world:serverNow() + 0.05)
		local run = session.training
		for _ = 1, Training.Tap.duration * 100 do
			world:fire("Training", player, "tap")
			world:advance(0.01)
		end
		t.lte(run.taps, Training.Tap.duration / Training.Tap.minGap + 2)
		world:advance(2)
		t.eq(session.training, nil)
		t.eq(messages(world, player, "end")[1].reason, "complete")
		world:assertNoErrors()
	end)

	t.test("hits on a target need the current target index and a sane position", function()
		local world, svc, player, session = setup()
		start(world, player, "Precision")
		world:advance(1.1) -- the server shows the first target one second in
		local run = session.training
		t.truthy(run and run.targetOpen, "first target is showing")
		world:fire("Training", player, "hit", 99, run.targetX, run.targetY)
		t.eq(run.reps, 0, "wrong index ignored")
		world:fire("Training", player, "hit", run.targetIndex, "x", run.targetY)
		world:fire("Training", player, "hit", run.targetIndex, 0 / 0, run.targetY)
		t.eq(run.reps, 0, "garbage coordinates ignored")
		world:fire("Training", player, "hit", run.targetIndex, run.targetX, run.targetY)
		t.eq(run.reps, 1)
		world:fire("Training", player, "hit", run.targetIndex, run.targetX, run.targetY)
		t.eq(run.reps, 1, "a target can be hit once")
		world:assertNoErrors()
	end)

	t.test("a target nobody hits counts as a miss and the set still finishes", function()
		local world, svc, player, session = setup()
		start(world, player, "Precision")
		world:advance(60)
		local finished = messages(world, player, "end")
		t.eq(#finished, 1)
		t.eq(finished[1].grades.miss, Training.Targets.reps)
		t.eq(finished[1].points, 0)
		t.eq(session.data.stats.trainingSessions, 0, "an empty session is not counted")
		world:assertNoErrors()
	end)

	t.test("walking away from the station ends the session", function()
		local world, svc, player, session = setup()
		start(world, player, "Haste")
		world:advance(2)
		world:placeCharacter(player, V.new(900, 3, 900))
		world:advance(1)
		t.eq(session.training, nil)
		t.eq(messages(world, player, "end")[1].reason, "left")
		world:assertNoErrors()
	end)

	t.test("dying during a session ends it", function()
		local world, svc, player, session = setup()
		start(world, player, "Haste")
		world:advance(2)
		player.Character.Humanoid.Health = 0
		world:advance(1)
		t.eq(session.training, nil)
		t.eq(messages(world, player, "end")[1].reason, "died")
	end)

	t.test("leaving the server mid-session cleans up without errors or late rewards", function()
		local world, svc, player, session = setup()
		start(world, player, "Haste")
		world:advance(3)
		local xp = session.data.xp
		world:leave(player)
		world:advance(30)
		t.eq(session.training, nil)
		t.eq(session.data.xp, xp)
		world:assertNoErrors()
	end)

	t.test("rewards are applied once, scaled by the level cap, and training points never skip the cap", function()
		local world, svc, player, session = setup(2)
		session.data.training.power.level = 0
		start(world, player, "Power")
		local info = messages(world, player, "start")[1]
		world:advance(info.startT - world:serverNow() + 0.1)
		for _ = 1, Training.Timing.reps do
			world:fire("Training", player, "press", world:serverNow())
			world:advance(Training.Timing.minGap + 0.01)
		end
		world:advance(2)
		local cap = Training.LevelCapBase + Training.LevelCapPerPlayerLevel * session.data.level
		t.lte(session.data.training.power.level, cap)
		t.eq(#messages(world, player, "end"), 1)
		-- stopping an already finished session does nothing
		world:fire("Training", player, "stop")
		t.eq(#messages(world, player, "end"), 1)
		world:assertNoErrors()
	end)
end
