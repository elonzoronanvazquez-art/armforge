--!strict
-- UI manager: creates the ScreenGui, scales it to the viewport, hosts the HUD and toasts, and opens one modal panel at
-- a time inside a shared window chrome. Panels are modules in client/UI with the shape:
--   { name, title, size: Vector2, build(content: Frame), refresh(), onOpen(args), onClose() }

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local Signal = require(Shared.Util.Signal)
local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local W = require(script.Parent.Widgets)

local C = Theme.colors

local UI = {}

export type Panel = {
	name: string,
	title: string,
	size: Vector2,
	build: (content: Frame) -> (),
	refresh: () -> (),
	onOpen: ((args: any) -> ())?,
	onClose: (() -> ())?,
}

UI.opened = Signal.new() :: Signal.Signal<string?>
UI.gui = nil :: ScreenGui?
UI.root = nil :: Frame?
UI.current = nil :: string?

local panels: { [string]: Panel } = {}
local windows: { [string]: Frame } = {}
local dimmer: TextButton
local scaleObj: UIScale

local function computeScale(): number
	local cam = workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(1280, 720)
	local base = math.min(vp.X / Theme.designSize.X, vp.Y / Theme.designSize.Y)
	local user = (Store.data and Store.data.settings and Store.data.settings.uiScale) or 1
	local touch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	local floor = if touch then 0.62 else 0.55
	return math.clamp(base, floor, 1.35) * user * (if touch then 1.08 else 1)
end

function UI.register(panel: Panel)
	panels[panel.name] = panel
end

function UI.modalOpen(): boolean
	return UI.current ~= nil
end

function UI.close()
	local name = UI.current
	if not name then
		return
	end
	UI.current = nil
	local win = windows[name]
	local panel = panels[name]
	if panel and panel.onClose then
		panel.onClose()
	end
	if win then
		TweenService:Create(win, TweenInfo.new(0.12), { Position = UDim2.fromScale(0.5, 0.53) }):Play()
		win.Visible = false
	end
	dimmer.Visible = false
	UI.opened:fire(nil)
end

function UI.open(name: string, args: any?)
	local panel = panels[name]
	if not panel then
		return
	end
	if UI.current == name then
		if panel.onOpen then
			panel.onOpen(args)
		end
		panel.refresh()
		return
	end
	if UI.current then
		UI.close()
	end
	UI.current = name
	local win = windows[name]
	dimmer.Visible = true
	win.Visible = true
	win.Position = UDim2.fromScale(0.5, 0.53)
	TweenService:Create(win, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.5, 0.5) }):Play()
	if panel.onOpen then
		panel.onOpen(args)
	end
	panel.refresh()
	UI.opened:fire(name)
end

function UI.toggle(name: string, args: any?)
	if UI.current == name then
		UI.close()
	else
		UI.open(name, args)
	end
end

local function buildWindow(panel: Panel, root: Frame)
	local win = W.card({
		Name = "Window_" .. panel.name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(panel.size.X, panel.size.Y),
		Visible = false,
		ZIndex = 20,
		Parent = root,
	})
	win:SetAttribute("BlocksWorldInput", true)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(panel.size.X, panel.size.Y)
	limit.Parent = win
	local header = W.frame({ Size = UDim2.new(1, 0, 0, 46), Parent = win })
	W.text({
		Text = panel.title,
		Font = Theme.fontBlack,
		TextSize = 20,
		Position = UDim2.fromOffset(18, 0),
		Size = UDim2.new(1, -70, 1, 0),
		TextColor3 = C.text,
		Parent = header,
	})
	local accent = W.frame({ Size = UDim2.new(1, -28, 0, 2), Position = UDim2.new(0, 14, 1, -2), BackgroundColor3 = C.accentDark, BackgroundTransparency = 0.2, Parent = header })
	accent.BorderSizePixel = 0
	W.button({
		Text = "X",
		Size = UDim2.fromOffset(34, 30),
		Position = UDim2.new(1, -44, 0, 8),
		textSize = 16,
		onClick = function()
			UI.close()
		end,
		Parent = header,
	})
	local content = W.frame({ Name = "Content", Position = UDim2.fromOffset(0, 48), Size = UDim2.new(1, 0, 1, -48), ClipsDescendants = true, Parent = win })
	panel.build(content)
	windows[panel.name] = win
end

function UI.start(modules: { Panel }, hud: { build: (root: Frame) -> () })
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "ArmforgeUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 10
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	UI.gui = gui

	local root = W.frame({ Name = "Root", Size = UDim2.fromScale(1, 1), Parent = gui })
	scaleObj = Instance.new("UIScale")
	scaleObj.Scale = computeScale()
	scaleObj.Parent = root
	-- the UIScale shrinks children, so give the root the inverse size to keep it filling the screen
	local function resize()
		scaleObj.Scale = computeScale()
		root.Size = UDim2.fromScale(1 / scaleObj.Scale, 1 / scaleObj.Scale)
	end
	resize()
	UI.root = root
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(resize)
	end
	Store.changed:connect(function()
		resize()
	end)

	hud.build(root)

	dimmer = W.new("TextButton", {
		Name = "Dimmer",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.black,
		BackgroundTransparency = 0.45,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		ZIndex = 15,
		Parent = root,
	})
	dimmer.Activated:Connect(function()
		UI.close()
	end)

	for _, panel in modules do
		UI.register(panel)
		buildWindow(panel, root)
	end

	Store.changed:connect(function()
		local name = UI.current
		if name then
			panels[name].refresh()
		end
	end)
	-- keep time-based labels (cooldowns, booster timers) fresh while a panel is open
	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < 0.4 then
			return
		end
		accum = 0
		local name = UI.current
		if name then
			panels[name].refresh()
		end
	end)
end

return UI
