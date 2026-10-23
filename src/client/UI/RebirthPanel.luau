--!strict
-- REBIRTH: the prestige reset. Spells out exactly what resets, what is kept, what you gain and what you need, and asks
-- for a deliberate press-and-hold confirmation. The rules shown here come straight from Config/Progression.Rebirth.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local ProgressionConfig = require(Shared.Config.Progression)
local BoosterConfig = require(Shared.Config.Boosters)
local Progression = require(Shared.Logic.Progression)
local Formulas = require(Shared.Logic.Formulas)
local Format = require(Shared.Util.Format)
local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local W = require(script.Parent.Widgets)
local Messages = require(script.Parent.Messages)
local UI = require(script.Parent.UI)

local C = Theme.colors

local Panel = {}
Panel.name = "Rebirth"
Panel.title = "REFORGE CORE: REBIRTH"
Panel.size = Vector2.new(820, 480)

local refs: { [string]: any } = {}
local holding = false
local holdStart = 0
local HOLD_TIME = 1.6

local RESET_TEXT: { [string]: string } = {
	coins = "Your coins",
	level = "Your level and XP",
	xp = "",
	skillPoints = "Skill points",
	skillRanks = "Learned skill ranks",
	armUpgradeLevels = "Arm upgrade levels (the arms stay yours)",
	trainingStats = "Training stats",
}

local function nearAltar(): boolean
	local char = Players.LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return false
	end
	for _, inst in CollectionService:GetTagged("RebirthAltar") do
		if inst:IsA("BasePart") and (inst.Position - hrp.Position).Magnitude <= 40 then
			return true
		end
	end
	return false
end

local function bullets(parent: Instance, items: { string }, color: Color3)
	for _, child in parent:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	for i, text in items do
		W.text({ Size = UDim2.new(1, 0, 0, 18), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, LayoutOrder = i, TextSize = 13, TextColor3 = color, Text = "-  " .. text, Parent = parent })
	end
end

function Panel.refresh()
	local d = Store.data
	if not d then
		return
	end
	local status = Progression.rebirthStatus(d)
	local rules = ProgressionConfig.Rebirth
	local resets: { string } = {}
	for key, on in (rules.resets :: { [string]: boolean }) do
		local text = RESET_TEXT[key]
		if on and text and text ~= "" then
			table.insert(resets, text)
		end
	end
	table.sort(resets)
	bullets(refs.resets, resets, C.bad)
	bullets(refs.keeps, rules.preserves, C.good)
	local rewards: { string } = {
		`+{Format.percent(rules.bonusPerRebirth.coins)} coins, permanently (total {Format.percent(Formulas.rebirthBonus(d.rebirths + 1, "coins"))})`,
		`+{Format.percent(rules.bonusPerRebirth.xp)} XP, +{Format.percent(rules.bonusPerRebirth.power)} damage, +{Format.percent(rules.bonusPerRebirth.training)} training`,
	}
	for id, n in (rules.reward.boosters :: { [string]: number }) do
		table.insert(rewards, `{n}x {BoosterConfig.Defs[id].name}`)
	end
	table.insert(rewards, "Access to islands and arms that need a Rebirth")
	bullets(refs.gains, rewards, C.accent)
	refs.count.Text = `Rebirths so far: {d.rebirths}`
	local lines: { { text: string, met: boolean } } = {
		{ text = `Level {rules.minLevel}`, met = d.level >= rules.minLevel },
		{ text = `{Format.commas(status.cost)} coins`, met = d.coins >= status.cost },
		{ text = "Standing at the Reforge Core", met = nearAltar() },
	}
	for i, line in lines do
		local l = refs.reqs:FindFirstChild("R" .. i) :: TextLabel
		l.Text = (if line.met then "OK    " else "NEED  ") .. line.text
		l.TextColor3 = if line.met then C.good else C.bad
	end
	local ready = status.eligible and nearAltar()
	W.setEnabled(refs.button, ready)
	refs.button.Text = if ready then "HOLD TO REBIRTH" elseif d.rebirths >= rules.maxRebirths then "MAX REBIRTHS" else "NOT READY"
end

local function setHold(on: boolean)
	holding = on
	holdStart = os.clock()
	if not on then
		refs.fill.Size = UDim2.fromScale(0, 1)
	end
end

function Panel.build(content: Frame)
	refs.count = W.text({ Position = UDim2.fromOffset(18, 4), Size = UDim2.new(1, -36, 0, 20), Font = Theme.fontBold, TextSize = 14, TextColor3 = C.shard, Text = "", Parent = content })
	local cols = W.frame({ Position = UDim2.fromOffset(14, 28), Size = UDim2.new(1, -28, 1, -120), Parent = content })
	W.list(Enum.FillDirection.Horizontal, 8).Parent = cols
	local function column(order: number, title: string, color: Color3): Frame
		local card = W.card({ Size = UDim2.new(1 / 3, -6, 1, 0), LayoutOrder = order, Parent = cols })
		W.padding(12, 10).Parent = card
		local stroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke
		stroke.Color = color
		stroke.Transparency = 0.4
		W.text({ Size = UDim2.new(1, 0, 0, 20), Font = Theme.fontBlack, TextSize = 14, TextColor3 = color, Text = title, Parent = card })
		local body = W.frame({ Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 1, -26), Parent = card })
		W.list(Enum.FillDirection.Vertical, 3).Parent = body
		return body
	end
	refs.resets = column(1, "WHAT RESETS", C.bad)
	refs.keeps = column(2, "WHAT YOU KEEP", C.good)
	refs.gains = column(3, "WHAT YOU GAIN", C.accent)

	refs.reqs = W.frame({ Position = UDim2.new(0, 18, 1, -86), Size = UDim2.new(0.5, 0, 0, 60), Parent = content })
	W.list(Enum.FillDirection.Vertical, 2).Parent = refs.reqs
	for i = 1, 3 do
		W.text({ Name = "R" .. i, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = i, TextSize = 13, Text = "", Parent = refs.reqs })
	end
	refs.button = W.button({
		Text = "HOLD TO REBIRTH",
		Size = UDim2.fromOffset(280, 52),
		Position = UDim2.new(1, -18, 1, -18),
		AnchorPoint = Vector2.new(1, 1),
		textSize = 16,
		style = "primary",
		Parent = content,
	})
	local fill = W.frame({ Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.shard, BackgroundTransparency = 0.2, ZIndex = 2, Parent = refs.button })
	W.corner(UDim.new(0, 8)).Parent = fill
	refs.fill = fill
	refs.button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local d = Store.data
			if d and Progression.rebirthStatus(d).eligible and nearAltar() then
				setHold(true)
			end
		end
	end)
	refs.button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			setHold(false)
		end
	end)
	RunService.Heartbeat:Connect(function()
		if holding then
			local k = (os.clock() - holdStart) / HOLD_TIME
			refs.fill.Size = UDim2.fromScale(math.clamp(k, 0, 1), 1)
			if k >= 1 then
				holding = false
				refs.fill.Size = UDim2.fromScale(0, 1)
				local result = Store.request("Rebirth")
				if Messages.report(result, nil, "Rebirth") then
					UI.close()
				end
			end
		end
	end)
end

function Panel.onClose()
	setHold(false)
end

return Panel
