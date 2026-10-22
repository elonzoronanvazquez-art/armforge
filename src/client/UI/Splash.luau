--!strict
-- Title splash: the ARMFORGE logo treatment shown while the world streams in. Letters are drawn as bold type with an ember
-- gradient, a forged-metal underline and a glow; it fades out once the server is ready and the character exists.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local W = require(script.Parent.Widgets)

local C = Theme.colors

local Splash = {}

function Splash.show(root: Frame)
	local overlay = W.frame({ Name = "Splash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.bg, BackgroundTransparency = 0, ZIndex = 100, Parent = root })
	overlay:SetAttribute("BlocksWorldInput", true)
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(46, 26, 22), Color3.fromRGB(14, 12, 20))
	grad.Rotation = 90
	grad.Parent = overlay

	local title = W.text({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(760, 120),
		Font = Theme.fontBlack,
		TextSize = 104,
		Text = "ARMFORGE",
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 101,
		Parent = overlay,
	})
	local titleGradient = Instance.new("UIGradient")
	titleGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 226, 150)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 140, 50)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 70, 30)),
	})
	titleGradient.Rotation = 90
	titleGradient.Parent = title
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = Color3.fromRGB(40, 20, 16)
	stroke.Parent = title

	local line = W.frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromOffset(0, 4), BackgroundColor3 = C.accent, BackgroundTransparency = 0, ZIndex = 101, Parent = overlay })
	W.corner(UDim.new(1, 0)).Parent = line
	TweenService:Create(line, TweenInfo.new(1.1, Enum.EasingStyle.Quart), { Size = UDim2.fromOffset(520, 4) }):Play()

	local tagline = W.text({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.6),
		Size = UDim2.fromOffset(700, 30),
		Font = Theme.fontBold,
		TextSize = 20,
		TextColor3 = C.sub,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "Forge the arms. Break the world.",
		ZIndex = 101,
		Parent = overlay,
	})
	local hint = W.text({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.fromOffset(500, 22),
		TextSize = 14,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "Loading the island...",
		ZIndex = 101,
		Parent = overlay,
	})

	task.spawn(function()
		local started = os.clock()
		local player = Players.LocalPlayer
		while os.clock() - started < 25 do
			local char = player.Character
			local ready = workspace:GetAttribute("ArmforgeReady") == true and char ~= nil and char:FindFirstChild("HumanoidRootPart") ~= nil
			if ready and os.clock() - started > 2.2 then
				break
			end
			task.wait(0.1)
		end
		hint.Text = "Click the rocks. Break them apart."
		task.wait(0.6)
		local fade = TweenInfo.new(0.9, Enum.EasingStyle.Quad)
		TweenService:Create(overlay, fade, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(title, fade, { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
		TweenService:Create(line, fade, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(tagline, fade, { TextTransparency = 1 }):Play()
		TweenService:Create(hint, fade, { TextTransparency = 1 }):Play()
		task.wait(1)
		overlay:Destroy()
	end)
end

return Splash
