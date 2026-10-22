--!strict
-- Small widget toolkit: every function returns plain Roblox GuiObjects styled from Theme. Keeping construction in one
-- place means panels stay short and every button, bar and card looks and behaves the same.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local C = Theme.colors

local Widgets = {}

type Props = { [string]: any }

-- Creates an instance of `class`, applies `props`, parents `children` under it.
function Widgets.new(class: string, props: Props?, children: { Instance }?): any
	local inst = Instance.new(class)
	if props then
		for k, v in props do
			if k ~= "Parent" then
				(inst :: any)[k] = v
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

function Widgets.corner(radius: UDim?): UICorner
	return Widgets.new("UICorner", { CornerRadius = radius or Theme.radius })
end

function Widgets.stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	return Widgets.new("UIStroke", {
		Color = color or C.stroke,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Widgets.padding(px: number, top: number?, bottom: number?): UIPadding
	return Widgets.new("UIPadding", {
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		PaddingTop = UDim.new(0, top or px),
		PaddingBottom = UDim.new(0, bottom or top or px),
	})
end

function Widgets.list(dir: Enum.FillDirection?, gap: number?, align: Enum.HorizontalAlignment?): UIListLayout
	return Widgets.new("UIListLayout", {
		FillDirection = dir or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, gap or 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
	})
end

function Widgets.frame(props: Props?): Frame
	local p: Props = { BackgroundTransparency = 1, BorderSizePixel = 0 }
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	return Widgets.new("Frame", p)
end

function Widgets.text(props: Props): TextLabel
	local p: Props = {
		BackgroundTransparency = 1,
		Font = Theme.font,
		TextColor3 = C.text,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = false,
		RichText = false,
		BorderSizePixel = 0,
	}
	for k, v in props do
		p[k] = v
	end
	return Widgets.new("TextLabel", p)
end

-- A raised card with gradient and copper-tinted border.
function Widgets.card(props: Props?): Frame
	local p: Props = { BackgroundColor3 = C.panel, BorderSizePixel = 0 }
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	local f = Widgets.new("Frame", p)
	Widgets.corner(Theme.radiusLg).Parent = f
	Widgets.stroke(C.stroke, 1.4, 0.2).Parent = f
	local grad = Widgets.new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(196, 190, 200)),
		Rotation = 90,
	})
	grad.Parent = f
	return f
end

-- Instances cannot carry Lua fields, so a button's enable/disable painter lives in a weak side table.
local painters: { [Instance]: (boolean) -> () } = setmetatable({}, { __mode = "k" }) :: any

function Widgets.setEnabled(btn: Instance, value: boolean)
	local paint = painters[btn]
	if paint then
		paint(value)
	end
end

-- Pressable button. `style` = "primary" (ember) | "good" | "ghost" | "danger". onClick runs on activation.
function Widgets.button(props: Props): any
	local style: string = props.style or "ghost"
	local base = if style == "primary" then C.accent elseif style == "good" then C.good elseif style == "danger" then C.bad else C.panelHi
	local textColor = if style == "ghost" then C.text else C.black
	local btn = Widgets.new("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = base,
		BorderSizePixel = 0,
		Font = Theme.fontBold,
		Text = props.text or props.Text or "",
		TextColor3 = textColor,
		TextSize = props.textSize or 16,
		Size = props.Size or UDim2.fromOffset(120, 38),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	})
	Widgets.corner(UDim.new(0, 8)).Parent = btn
	local stroke = Widgets.stroke(if style == "ghost" then C.stroke else base:Lerp(Color3.new(1, 1, 1), 0.35), 1.2, 0.1)
	stroke.Parent = btn
	local enabled = true
	local hover = false

	local function paint()
		local color = base
		if not enabled then
			color = C.panelLo
			btn.TextColor3 = C.dim
		else
			btn.TextColor3 = textColor
			if hover then
				color = base:Lerp(Color3.new(1, 1, 1), 0.14)
			end
		end
		TweenService:Create(btn, TweenInfo.new(0.1), { BackgroundColor3 = color }):Play()
	end
	btn.MouseEnter:Connect(function()
		hover = true
		paint()
	end)
	btn.MouseLeave:Connect(function()
		hover = false
		paint()
	end)
	btn.Activated:Connect(function()
		if enabled and props.onClick then
			props.onClick()
		end
	end)
	painters[btn] = function(value: boolean)
		enabled = value
		paint()
	end
	if props.enabled == false then
		enabled = false
		paint()
	end
	return btn
end

export type Bar = { root: Frame, set: (frac: number, text: string?) -> (), fill: Frame, label: TextLabel }

-- Horizontal progress bar with optional overlaid text.
function Widgets.bar(props: Props): Bar
	local root = Widgets.new("Frame", {
		BackgroundColor3 = C.panelLo,
		BorderSizePixel = 0,
		Size = props.Size or UDim2.new(1, 0, 0, 12),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		ClipsDescendants = true,
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	})
	Widgets.corner(UDim.new(0, (props.radius or 6))).Parent = root
	Widgets.stroke(C.stroke, 1, 0.4).Parent = root
	local fill = Widgets.new("Frame", {
		BackgroundColor3 = props.color or C.accent,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = root,
	})
	Widgets.corner(UDim.new(0, (props.radius or 6))).Parent = fill
	local sheen = Widgets.new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(180, 180, 180)),
		Rotation = 90,
	})
	sheen.Parent = fill
	local label = Widgets.text({
		Size = UDim2.fromScale(1, 1),
		TextSize = props.textSize or 11,
		Font = Theme.fontBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "",
		ZIndex = 2,
		Parent = root,
	})
	local bar: any = { root = root, fill = fill, label = label }
	function bar.set(frac: number, text: string?)
		TweenService:Create(fill, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1) }):Play()
		if text then
			label.Text = text
		end
	end
	return bar
end

-- A circle currency icon (coin) / diamond (shard), drawn from frames so no font glyph is needed.
function Widgets.coinIcon(size: number, parent: Instance?): Frame
	local f = Widgets.new("Frame", { Size = UDim2.fromOffset(size, size), BackgroundColor3 = C.coin, BorderSizePixel = 0, Parent = parent })
	Widgets.corner(UDim.new(1, 0)).Parent = f
	Widgets.stroke(Color3.fromRGB(176, 120, 30), 1.5).Parent = f
	local inner = Widgets.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.52, 0.52),
		BackgroundColor3 = Color3.fromRGB(255, 232, 150),
		BorderSizePixel = 0,
		Parent = f,
	})
	Widgets.corner(UDim.new(1, 0)).Parent = inner
	return f
end

function Widgets.shardIcon(size: number, parent: Instance?): Frame
	local f = Widgets.new("Frame", {
		Size = UDim2.fromOffset(size * 0.72, size * 0.72),
		BackgroundColor3 = C.shard,
		BorderSizePixel = 0,
		Rotation = 45,
		Parent = parent,
	})
	Widgets.corner(UDim.new(0, 3)).Parent = f
	Widgets.stroke(Color3.fromRGB(120, 70, 190), 1.5).Parent = f
	local wrap = Widgets.new("Frame", { Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, Parent = parent })
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Parent = wrap
	return wrap
end

-- Currency row: icon + number, returns the container and a setter.
function Widgets.currency(kind: string, size: number): { root: Frame, set: (value: number) -> () }
	local root = Widgets.frame({ Size = UDim2.new(0, 0, 0, size), AutomaticSize = Enum.AutomaticSize.X })
	Widgets.list(Enum.FillDirection.Horizontal, 6).Parent = root
	local icon = if kind == "shard" then Widgets.shardIcon(size, root) else Widgets.coinIcon(size, root)
	icon.LayoutOrder = 1
	local label = Widgets.text({
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Theme.fontBold,
		TextSize = size - 2,
		Text = "0",
		TextColor3 = if kind == "shard" then C.shard else C.coin,
		LayoutOrder = 2,
		Parent = root,
	})
	local shown = 0
	local target = 0
	local running = false
	local function format(n: number): string
		local s = tostring(math.floor(n))
		local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
		return (out:gsub("^,", ""))
	end
	local function animate()
		if running then
			return
		end
		running = true
		task.spawn(function()
			while math.abs(shown - target) > 0.5 do
				shown += (target - shown) * 0.25
				if math.abs(shown - target) < 1 then
					shown = target
				end
				label.Text = format(shown)
				task.wait(0.03)
			end
			label.Text = format(target)
			running = false
		end)
	end
	return {
		root = root,
		set = function(value: number)
			target = value
			if math.abs(target - shown) > 1e7 then
				shown = target
			end
			animate()
		end,
	}
end

-- Rounded pill label (rarity tags, state badges).
function Widgets.pill(text: string, color: Color3, textColor: Color3?, props: Props?): TextLabel
	local p: Props = {
		Text = text,
		Font = Theme.fontBold,
		TextSize = 11,
		TextColor3 = textColor or C.black,
		BackgroundColor3 = color,
		BackgroundTransparency = 0,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
	}
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	local l = Widgets.text(p)
	Widgets.corner(UDim.new(1, 0)).Parent = l
	Widgets.padding(8, 0).Parent = l
	return l
end

function Widgets.scroll(props: Props): ScrollingFrame
	local p: Props = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = C.strokeHi,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}
	for k, v in props do
		p[k] = v
	end
	return Widgets.new("ScrollingFrame", p)
end

-- Is the given input over any visible GUI that should swallow clicks?
function Widgets.overGui(playerGui: PlayerGui, position: Vector2): boolean
	for _, obj in playerGui:GetGuiObjectsAtPosition(position.X, position.Y) do
		if obj:IsA("GuiButton") or (obj:GetAttribute("BlocksWorldInput") == true) then
			return true
		end
	end
	return false
end

function Widgets.isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

return Widgets
