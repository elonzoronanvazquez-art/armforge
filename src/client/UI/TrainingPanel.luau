--!strict
-- TRAINING: the four station mini-games (timing press, speed tap, target range, breathing rhythm). The SERVER owns the
-- clock and the grading (services/TrainingService); this panel only draws what the server describes and reports presses.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local Net = require(Shared.Net)
local Training = require(Shared.Config.Training)
local Formulas = require(Shared.Logic.Formulas)
local TrainingLogic = require(Shared.Logic.TrainingLogic)
local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local W = require(script.Parent.Widgets)
local UI = require(script.Parent.UI)
local Notifications = require(script.Parent.Notifications)
local EffectsController = require(script.Parent.Parent.Controllers.EffectsController)

local C = Theme.colors

local Panel = {}
Panel.name = "Training"
Panel.title = "TRAINING YARD"
Panel.size = Vector2.new(640, 480)

local remotes: Net.Remotes
local refs: { [string]: any } = {}
local stationId = "Power"
local phase = "idle" -- idle | playing | result
local info: any = nil
local repCount = 0
local tapCount = 0
local activeTarget: { i: number, x: number, y: number, appear: number, visible: number }? = nil
local lastTapSent = 0

local GRADE_COLOR: { [string]: Color3 } = {
	perfect = Color3.fromRGB(255, 226, 110),
	great = Color3.fromRGB(120, 230, 150),
	good = Color3.fromRGB(120, 190, 255),
	miss = Color3.fromRGB(255, 110, 100),
}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function clearArena()
	for _, child in refs.arena:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	refs.dynamic = {}
end

local function setGrade(grade: string)
	refs.grade.Text = string.upper(grade) .. "!"
	refs.grade.TextColor3 = GRADE_COLOR[grade] or C.text
	refs.grade.TextTransparency = 0
	task.delay(0.5, function()
		if refs.grade.Text == string.upper(grade) .. "!" then
			refs.grade.TextTransparency = 0.6
		end
	end)
end

local function updateHeader()
	local d = Store.data
	if not d then
		return
	end
	local station = Training.Stations[stationId]
	local stat = station.stat
	local entry = d.training[stat]
	local cap = Formulas.trainingLevelCap(stat, d.level)
	refs.title.Text = string.upper(station.name)
	refs.blurb.Text = station.blurb
	refs.level.Text = `{Training.Stats[stat].name} Lv {entry.level}/{cap}   ·   {Training.Stats[stat].text}`
	local need = Formulas.trainingPointsToNext(entry.level)
	if entry.level >= cap then
		refs.bar.set(1, "Capped for your level. Level up to train further.")
	else
		refs.bar.set(entry.points / need, `{entry.points} / {need} training points`)
	end
	local locked = d.level < station.unlockLevel
	refs.start.Visible = phase ~= "playing"
	refs.start.Text = if locked then `LOCKED: REACH LEVEL {station.unlockLevel}` elseif phase == "result" then "TRAIN AGAIN" else "START TRAINING"
	W.setEnabled(refs.start, not locked)
end

function Panel.refresh()
	updateHeader()
end

-- Mini-game rendering ------------------------------------------------------------------------------------------------------

local function buildTiming()
	local track = W.frame({ Position = UDim2.new(0.5, -260, 0.5, -20), Size = UDim2.fromOffset(520, 40), BackgroundColor3 = C.panelLo, BackgroundTransparency = 0, Parent = refs.arena })
	W.corner(UDim.new(0, 8)).Parent = track
	W.stroke(C.stroke, 1.5).Parent = track
	local function zone(width: number, color: Color3, z: number)
		local f = W.frame({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(info.zone, 0, 0, 0), Size = UDim2.new(width * 2, 0, 1, 0), BackgroundColor3 = color, BackgroundTransparency = 0.2, ZIndex = z, Parent = track })
		W.corner(UDim.new(0, 6)).Parent = f
	end
	zone(info.zoneGood, GRADE_COLOR.good, 2)
	zone(Training.Timing.great, GRADE_COLOR.great, 3)
	zone(info.zonePerfect, GRADE_COLOR.perfect, 4)
	local marker = W.frame({ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(8, 56), Position = UDim2.fromScale(0, 0.5), BackgroundColor3 = C.text, BackgroundTransparency = 0, ZIndex = 6, Parent = track })
	W.corner(UDim.new(1, 0)).Parent = marker
	W.stroke(C.black, 1.5).Parent = marker
	refs.dynamic.marker = marker
	W.text({ Position = UDim2.new(0, 0, 1, 16), Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.sub, TextSize = 14, Text = "Press SPACE (or click / tap) when the bar crosses the glowing zone", Parent = track })
end

local function buildTap()
	local btn = W.new("TextButton", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(150, 150),
		BackgroundColor3 = C.accent,
		Text = "TAP!",
		Font = Theme.fontBlack,
		TextSize = 34,
		TextColor3 = C.black,
		AutoButtonColor = false,
		Parent = refs.arena,
	})
	W.corner(UDim.new(1, 0)).Parent = btn
	W.stroke(Color3.fromRGB(255, 226, 180), 4).Parent = btn
	refs.dynamic.tapButton = btn
	refs.dynamic.timeBar = W.bar({ Position = UDim2.new(0.5, -200, 0, 10), Size = UDim2.fromOffset(400, 16), color = C.accent, textSize = 11, Parent = refs.arena })
	refs.dynamic.tapText = W.text({ Position = UDim2.new(0.5, -200, 1, -30), Size = UDim2.fromOffset(400, 22), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.sub, TextSize = 14, Text = "Tap as fast as you can!", Parent = refs.arena })
end

local function buildTargets()
	local field = W.frame({ Size = UDim2.new(0, 520, 1, -40), Position = UDim2.new(0.5, -260, 0, 14), BackgroundColor3 = C.panelLo, BackgroundTransparency = 0, Parent = refs.arena })
	W.corner(UDim.new(0, 10)).Parent = field
	W.stroke(C.stroke, 1.5).Parent = field
	refs.dynamic.field = field
	W.text({ Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.dim, TextSize = 14, Text = "Click each target as it flashes", Parent = field })
end

local function buildRhythm()
	local cx = W.frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(90, 90), BackgroundColor3 = C.panelLo, BackgroundTransparency = 0, Parent = refs.arena })
	W.corner(UDim.new(1, 0)).Parent = cx
	W.stroke(GRADE_COLOR.perfect, 3).Parent = cx
	local ring = W.frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(240, 240), BackgroundTransparency = 1, Parent = refs.arena })
	W.corner(UDim.new(1, 0)).Parent = ring
	local stroke = W.stroke(C.accent, 5)
	stroke.Parent = ring
	refs.dynamic.ring = ring
	refs.dynamic.core = cx
	W.text({ Position = UDim2.new(0.5, -200, 1, -30), Size = UDim2.fromOffset(400, 22), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.sub, TextSize = 14, Text = "Press SPACE (or click / tap) as each ring lands on the circle", Parent = refs.arena })
end

local function startGame(payload: any)
	info = payload
	phase = "playing"
	repCount = 0
	tapCount = 0
	activeTarget = nil
	refs.grade.Text = ""
	refs.result.Visible = false
	refs.arena.Visible = true
	clearArena()
	local game = payload.game
	if game == "Timing" then
		buildTiming()
	elseif game == "Tap" then
		buildTap()
	elseif game == "Targets" then
		buildTargets()
	else
		buildRhythm()
	end
	updateHeader()
end

local function press()
	if phase ~= "playing" or not info then
		return
	end
	local game = info.game
	if game == "Timing" or game == "Rhythm" then
		remotes.Training:FireServer("press", now())
	elseif game == "Tap" then
		if os.clock() - lastTapSent >= 0.085 then
			lastTapSent = os.clock()
			tapCount += 1
			remotes.Training:FireServer("tap")
			local btn = refs.dynamic.tapButton
			if btn then
				btn.Size = UDim2.fromOffset(136, 136)
				task.delay(0.05, function()
					if btn.Parent then
						btn.Size = UDim2.fromOffset(150, 150)
					end
				end)
			end
		end
	end
end

local function clickArena(position: Vector2)
	if phase ~= "playing" or not info then
		return
	end
	if info.game == "Targets" then
		local field = refs.dynamic.field
		local t = activeTarget
		if field and t then
			local nx = (position.X - field.AbsolutePosition.X) / math.max(1, field.AbsoluteSize.X)
			local ny = (position.Y - field.AbsolutePosition.Y) / math.max(1, field.AbsoluteSize.Y)
			remotes.Training:FireServer("hit", t.i, nx, ny)
		end
	else
		press()
	end
end

local function showResult(p: any)
	phase = "result"
	refs.arena.Visible = false
	refs.result.Visible = true
	local stat = Training.Stats[p.stat]
	local lines = {
		`Points earned: {p.points}   ·   XP: {p.xp}`,
		`{stat.name} is now level {p.level}` .. (if p.levelsGained > 0 then `   (+{p.levelsGained}!)` else ""),
	}
	if p.capped then
		table.insert(lines, "Capped for your player level: level up to train further.")
	end
	local g = p.grades or {}
	table.insert(lines, `Perfect {g.perfect or 0}   Great {g.great or 0}   Good {g.good or 0}   Missed {g.miss or 0}`)
	refs.resultText.Text = table.concat(lines, "\n")
	refs.resultTitle.Text = if p.reason == "complete" then "SESSION COMPLETE" else "SESSION ENDED"
	EffectsController.sound(if p.levelsGained > 0 then "LevelUp" else "Upgrade", nil, 0.8, 1)
	if p.levelsGained > 0 then
		Notifications.toast(`{stat.name} increased to level {p.level}!`, "good")
	end
	updateHeader()
end

local function onTrainingS(kind: string, p: any)
	if kind == "start" then
		if p.station == stationId and UI.current == "Training" then
			startGame(p)
		end
	elseif kind == "grade" then
		if p.grade then
			setGrade(p.grade)
		end
		if p.reps then
			repCount = p.reps
		end
		if p.tap then
			tapCount = p.tap
		end
		if p.i and activeTarget and activeTarget.i == p.i then
			activeTarget = nil
			local t = refs.dynamic.targetFrame
			if t then
				t:Destroy()
				refs.dynamic.targetFrame = nil
			end
		end
	elseif kind == "target" then
		activeTarget = { i = p.i, x = p.x, y = p.y, appear = p.appear, visible = p.visible }
		local field = refs.dynamic.field
		if field then
			local old = refs.dynamic.targetFrame
			if old then
				old:Destroy()
			end
			local size = math.floor(info.radius * 2 * 520)
			local disc = W.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(p.x, p.y),
				Size = UDim2.fromOffset(size, size),
				BackgroundColor3 = C.bad,
				Parent = field,
			})
			W.corner(UDim.new(1, 0)).Parent = disc
			W.stroke(Color3.new(1, 1, 1), 3).Parent = disc
			local eye = W.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.4, 0.4), BackgroundColor3 = Color3.new(1, 1, 1), Parent = disc })
			W.corner(UDim.new(1, 0)).Parent = eye
			refs.dynamic.targetFrame = disc
			refs.dynamic.targetEye = eye
		end
	elseif kind == "end" then
		activeTarget = nil
		if p.station == stationId then
			showResult(p)
		end
	elseif kind == "denied" then
		Notifications.toast(p.reason, "warn")
	end
end

local function step()
	if phase ~= "playing" or not info then
		return
	end
	local t = now()
	local game = info.game
	refs.rep.Text = ""
	if t < info.startT then
		refs.grade.Text = tostring(math.ceil(info.startT - t))
		refs.grade.TextColor3 = C.text
		refs.grade.TextTransparency = 0
	end
	if game == "Timing" then
		local marker = refs.dynamic.marker
		if marker then
			local pos = if t >= info.startT then TrainingLogic.sweep(t, info.startT, info.period) else 0
			marker.Position = UDim2.fromScale(pos, 0.5)
		end
		refs.rep.Text = `Rep {math.min(repCount + 1, info.reps)} / {info.reps}`
	elseif game == "Tap" then
		local left = math.max(0, info.startT + info.duration - t)
		local bar = refs.dynamic.timeBar
		if bar then
			bar.set(left / info.duration, string.format("%.1fs", left))
		end
		local text = refs.dynamic.tapText
		if text then
			local elapsed = math.max(0.1, t - info.startT)
			text.Text = if t < info.startT then "Get ready..." else `Taps {tapCount}  ·  {string.format("%.1f", tapCount / elapsed)} per second`
		end
	elseif game == "Targets" then
		refs.rep.Text = `Target {math.min(repCount + 1, info.reps)} / {info.reps}`
		local t2 = activeTarget
		local eye = refs.dynamic.targetEye
		if t2 and eye and eye.Parent then
			local k = math.clamp((t - t2.appear) / t2.visible, 0, 1)
			eye.Size = UDim2.fromScale(0.9 * (1 - k) + 0.1, 0.9 * (1 - k) + 0.1)
		end
	elseif game == "Rhythm" then
		local first = info.startT + info.lead
		local k = math.floor((t - first) / info.period + 0.5)
		local nextBeat = math.clamp(math.ceil((t - first - 0.05) / info.period), 0, info.beats - 1)
		local beatTime = first + nextBeat * info.period
		local frac = math.clamp((beatTime - t) / info.period, 0, 1.2)
		local ring = refs.dynamic.ring
		if ring then
			local size = 90 + 190 * frac
			ring.Size = UDim2.fromOffset(size, size)
			ring.Visible = t < first + info.beats * info.period
		end
		local core = refs.dynamic.core
		if core and math.abs(t - (first + k * info.period)) < 0.06 then
			core.BackgroundColor3 = C.accent
		elseif core then
			core.BackgroundColor3 = C.panelLo
		end
		refs.rep.Text = `Beats hit {repCount} / {info.beats}`
	end
end

function Panel.build(content: Frame)
	remotes = Net.client()
	refs.title = W.text({ Position = UDim2.fromOffset(20, 2), Size = UDim2.new(1, -40, 0, 24), Font = Theme.fontBlack, TextSize = 20, Text = "", Parent = content })
	refs.blurb = W.text({ Position = UDim2.fromOffset(20, 26), Size = UDim2.new(1, -40, 0, 18), TextSize = 13, TextColor3 = C.sub, Text = "", Parent = content })
	refs.level = W.text({ Position = UDim2.fromOffset(20, 48), Size = UDim2.new(1, -40, 0, 18), TextSize = 12, TextColor3 = C.accent, Font = Theme.fontBold, Text = "", Parent = content })
	refs.bar = W.bar({ Position = UDim2.fromOffset(20, 70), Size = UDim2.new(1, -40, 0, 18), color = C.good, textSize = 11, Parent = content })

	refs.arena = W.card({ Position = UDim2.fromOffset(20, 98), Size = UDim2.new(1, -40, 0, 250), BackgroundColor3 = C.panelLo, Parent = content })
	refs.arena:SetAttribute("BlocksWorldInput", true)
	refs.dynamic = {}
	refs.arenaClick = W.new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 8, Parent = refs.arena })
	refs.arenaClick.MouseButton1Down:Connect(function(x: number, y: number)
		clickArena(Vector2.new(x, y))
	end)

	refs.grade = W.text({ Position = UDim2.new(0, 20, 0, 354), Size = UDim2.fromOffset(240, 36), Font = Theme.fontBlack, TextSize = 28, Text = "", Parent = content })
	refs.rep = W.text({ Position = UDim2.new(1, -20, 0, 358), AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(260, 28), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 15, TextColor3 = C.sub, Font = Theme.fontBold, Text = "", Parent = content })

	refs.result = W.card({ Position = UDim2.fromOffset(20, 98), Size = UDim2.new(1, -40, 0, 250), Visible = false, Parent = content })
	W.padding(24, 20).Parent = refs.result
	refs.resultTitle = W.text({ Size = UDim2.new(1, 0, 0, 30), Font = Theme.fontBlack, TextSize = 24, TextColor3 = C.accent, Text = "", Parent = refs.result })
	refs.resultText = W.text({ Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextSize = 16, Text = "", Parent = refs.result })

	refs.start = W.button({
		Text = "START TRAINING",
		Size = UDim2.fromOffset(240, 44),
		Position = UDim2.new(0.5, 0, 1, -14),
		AnchorPoint = Vector2.new(0.5, 1),
		textSize = 16,
		style = "primary",
		onClick = function()
			phase = "idle"
			remotes.Training:FireServer("start", stationId)
		end,
		Parent = content,
	})

	remotes.TrainingS.OnClientEvent:Connect(onTrainingS)
	RunService.RenderStepped:Connect(step)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UI.current ~= "Training" then
			return
		end
		if input.KeyCode == Enum.KeyCode.Space then
			press()
		end
	end)
end

function Panel.onOpen(args: any)
	if args and type(args.stationId) == "string" and Training.Stations[args.stationId] then
		if args.stationId ~= stationId then
			phase = "idle"
		end
		stationId = args.stationId
	end
	if phase ~= "playing" then
		phase = "idle"
		refs.result.Visible = false
		refs.arena.Visible = true
		clearArena()
		refs.grade.Text = ""
		refs.rep.Text = ""
		W.text({ Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, TextColor3 = C.sub, TextSize = 16, Text = Training.Stations[stationId].blurb .. "\n\nPress START when you are ready.", Parent = refs.arena })
	end
	updateHeader()
end

function Panel.onClose()
	if phase == "playing" then
		remotes.Training:FireServer("stop")
	end
	phase = "idle"
end

return Panel
