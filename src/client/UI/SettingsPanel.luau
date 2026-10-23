--!strict
-- MENU: audio and comfort settings (saved with the player's data) plus a controls cheat sheet.

local UserInputService = game:GetService("UserInputService")

local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local W = require(script.Parent.Widgets)

local C = Theme.colors

local Panel = {}
Panel.name = "Settings"
Panel.title = "MENU"
Panel.size = Vector2.new(720, 470)

local refs: { [string]: any } = {}
local dragging: string? = nil

local function send(key: string, value: any)
	Store.request("SetSetting", { key = key, value = value })
end

-- A horizontal slider; calls onChange(value) while dragging and onCommit(value) on release.
local function slider(parent: Instance, order: number, label: string, min: number, max: number, key: string): any
	local row = W.frame({ Size = UDim2.new(1, 0, 0, 40), LayoutOrder = order, Parent = parent })
	W.text({ Size = UDim2.new(0.4, 0, 1, 0), Font = Theme.fontBold, TextSize = 14, Text = label, Parent = row })
	local value = W.text({ Position = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(50, 40), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 13, TextColor3 = C.accent, Text = "", Parent = row })
	local track = W.new("TextButton", {
		Position = UDim2.new(0.4, 0, 0.5, -5),
		Size = UDim2.new(0.5, -60, 0, 10),
		BackgroundColor3 = C.panelLo,
		AutoButtonColor = false,
		Text = "",
		Parent = row,
	})
	W.corner(UDim.new(1, 0)).Parent = track
	W.stroke(C.stroke, 1, 0.3).Parent = track
	local fill = W.frame({ Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = C.accent, BackgroundTransparency = 0, Parent = track })
	W.corner(UDim.new(1, 0)).Parent = fill
	local knob = W.frame({ Size = UDim2.fromOffset(18, 18), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = C.text, BackgroundTransparency = 0, ZIndex = 2, Parent = track })
	W.corner(UDim.new(1, 0)).Parent = knob
	local obj: any = { track = track, fill = fill, knob = knob, value = value, min = min, max = max, key = key }
	function obj.set(v: number)
		local f = math.clamp((v - min) / (max - min), 0, 1)
		fill.Size = UDim2.fromScale(f, 1)
		knob.Position = UDim2.fromScale(f, 0.5)
		value.Text = string.format(if max <= 2 then "%.0f%%" else "%.2f", if max <= 2 then v * 100 else v)
	end
	local function fromX(x: number): number
		local f = math.clamp((x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
		return min + (max - min) * f
	end
	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = key
			obj.set(fromX(input.Position.X))
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging == key and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			obj.set(fromX(input.Position.X))
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if dragging == key and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			dragging = nil
			local f = math.clamp((fill.AbsoluteSize.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
			send(key, min + (max - min) * f)
		end
	end)
	return obj
end

local function toggle(parent: Instance, order: number, label: string, key: string): any
	local row = W.frame({ Size = UDim2.new(1, 0, 0, 36), LayoutOrder = order, Parent = parent })
	W.text({ Size = UDim2.new(0.7, 0, 1, 0), Font = Theme.fontBold, TextSize = 14, Text = label, Parent = row })
	local btn = W.button({
		Text = "ON",
		Size = UDim2.fromOffset(80, 28),
		Position = UDim2.new(1, 0, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		textSize = 13,
		style = "primary",
		onClick = function()
			local d = Store.data
			send(key, not d.settings[key])
		end,
		Parent = row,
	})
	return btn
end

function Panel.refresh()
	local d = Store.data
	if not d then
		return
	end
	if dragging == nil then
		refs.sfx.set(d.settings.sfx)
		refs.shake.set(d.settings.shake)
		refs.scale.set(d.settings.uiScale)
	end
	refs.reduce.Text = if d.settings.reduceFx then "ON" else "OFF"
	refs.numbers.Text = if d.settings.damageNumbers then "ON" else "OFF"
end

function Panel.build(content: Frame)
	local left = W.frame({ Position = UDim2.fromOffset(18, 8), Size = UDim2.new(0.5, -26, 1, -20), Parent = content })
	W.list(Enum.FillDirection.Vertical, 6).Parent = left
	W.text({ Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 0, Font = Theme.fontBlack, TextSize = 14, TextColor3 = C.accent, Text = "SETTINGS", Parent = left })
	refs.sfx = slider(left, 1, "Sound effects", 0, 1, "sfx")
	refs.shake = slider(left, 2, "Camera shake", 0, 1, "shake")
	refs.scale = slider(left, 3, "Interface size", 0.7, 1.4, "uiScale")
	refs.reduce = toggle(left, 4, "Reduce effects (better on phones)", "reduceFx")
	refs.numbers = toggle(left, 5, "Damage numbers", "damageNumbers")

	local right = W.card({ Position = UDim2.new(0.5, 4, 0, 8), Size = UDim2.new(0.5, -22, 1, -20), Parent = content })
	W.padding(14, 12).Parent = right
	W.text({ Size = UDim2.new(1, 0, 0, 20), Font = Theme.fontBlack, TextSize = 14, TextColor3 = C.accent, Text = "CONTROLS", Parent = right })
	local lines = {
		"Punch: click / tap PUNCH / R2 (hold to keep striking)",
		"Skills: 1  2  3  4   (or tap the skill slots)",
		"F  Arms & upgrades        K  Skills & training",
		"B  Boosters        M  Islands        R  Rebirth",
		"O  This menu        E  Use stations (prompts)",
		"",
		"Punch rocks to break them, collect coins and XP,",
		"upgrade your arms, train at the Training Yard,",
		"then sail to new islands from the Skyport.",
	}
	local list = W.frame({ Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 1, -26), Parent = right })
	W.list(Enum.FillDirection.Vertical, 3).Parent = list
	for i, line in lines do
		W.text({ Size = UDim2.new(1, 0, 0, 18), LayoutOrder = i, TextSize = 13, TextColor3 = if i > 5 then C.sub else C.text, TextWrapped = true, Text = line, Parent = list })
	end
end

return Panel
