--!strict
-- Handles the server's Notify remote: reward popups, level-up banner, toasts, island arrival, rebirth flash.

local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local Net = require(Shared.Net)
local BoosterConfig = require(Shared.Config.Boosters)
local Format = require(Shared.Util.Format)
local Theme = require(script.Parent.Theme)
local W = require(script.Parent.Widgets)
local EffectsController = require(script.Parent.Parent.Controllers.EffectsController)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)

local C = Theme.colors

local Notifications = {}

local root: Frame
local toastHolder: Frame
local feed: Frame

local function tweenOut(obj: GuiObject, delay: number, duration: number)
	task.delay(delay, function()
		if obj.Parent then
			TweenService:Create(obj, TweenInfo.new(duration), { BackgroundTransparency = 1 }):Play()
			for _, d in obj:GetDescendants() do
				if d:IsA("TextLabel") then
					TweenService:Create(d, TweenInfo.new(duration), { TextTransparency = 1 }):Play()
				elseif d:IsA("UIStroke") then
					TweenService:Create(d, TweenInfo.new(duration), { Transparency = 1 }):Play()
				end
			end
			task.delay(duration, function()
				obj:Destroy()
			end)
		end
	end)
end

function Notifications.toast(text: string, kind: string?)
	local color = if kind == "good" then C.good elseif kind == "bad" then C.bad elseif kind == "warn" then C.warn else C.text
	local card = W.card({ Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, Parent = toastHolder })
	W.padding(14, 0).Parent = card
	W.text({ Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, Font = Theme.fontBold, TextSize = 15, TextColor3 = color, Text = text, Parent = card })
	tweenOut(card, 2.6, 0.4)
end

local function feedLine(text: string, color: Color3)
	local line = W.text({
		Size = UDim2.fromOffset(240, 18),
		Font = Theme.fontBold,
		TextSize = 14,
		TextColor3 = color,
		Text = text,
		Parent = feed,
	})
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Color = C.black
	stroke.Parent = line
	tweenOut(line, 3.2, 0.5)
end

local function onReward(p: any)
	if p.coins > 0 then
		EffectsController.floatText(p.pos + Vector3.new(0, 4, 0), `+{Format.compact(p.coins)}`, C.coin, 1.5, 6)
	end
	if p.xp > 0 then
		task.delay(0.12, function()
			EffectsController.floatText(p.pos + Vector3.new(0, 3, 0), `+{Format.compact(p.xp)} XP`, C.xp, 1.1, 5)
		end)
	end
	if p.shards > 0 then
		task.delay(0.24, function()
			EffectsController.floatText(p.pos + Vector3.new(0, 5.5, 0), `+{p.shards} SHARD{if p.shards > 1 then "S" else ""}`, C.shard, 1.4, 7)
		end)
	end
	EffectsController.sound("Coin", nil, 1, 1)
	feedLine(`{p.rock}: +{Format.compact(p.coins)} coins, +{Format.compact(p.xp)} XP{if p.shards > 0 then `, +{p.shards} shards` else ""}`, if p.rare then C.shard else C.text)
end

local function onCreatureReward(p: any)
	local tint = if p.boss then C.shard elseif p.tier == "elite" then C.accent else C.text
	if p.coins > 0 then
		EffectsController.floatText(p.pos + Vector3.new(0, 7, 0), `+{Format.compact(p.coins)}`, C.coin, if p.boss then 2 else 1.6, 7)
	end
	if p.xp > 0 then
		task.delay(0.14, function()
			EffectsController.floatText(p.pos + Vector3.new(0, 5.5, 0), `+{Format.compact(p.xp)} XP`, C.xp, 1.2, 6)
		end)
	end
	if p.shards > 0 then
		task.delay(0.28, function()
			EffectsController.floatText(p.pos + Vector3.new(0, 9, 0), `+{p.shards} SHARDS`, C.shard, 1.5, 8)
		end)
	end
	EffectsController.sound("Coin", nil, 1, if p.boss then 0.8 else 1)
	feedLine(`{p.name} defeated: +{Format.compact(p.coins)} coins, +{Format.compact(p.xp)} XP{if p.shards > 0 then `, +{p.shards} shards` else ""}`, tint)
end

local function onLevelUp(p: any)
	EffectsController.sound("LevelUp", nil, 1, 1)
	CameraController.shake(0.25, 0.3)
	local card = W.card({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 90),
		Size = UDim2.fromOffset(360, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 30,
		Parent = root,
	})
	W.padding(16).Parent = card
	W.list(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Center).Parent = card
	local stroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Color = C.accent
	stroke.Thickness = 3
	W.text({ Size = UDim2.new(1, 0, 0, 20), Font = Theme.fontBlack, TextSize = 14, TextColor3 = C.accent, TextXAlignment = Enum.TextXAlignment.Center, Text = "LEVEL UP", LayoutOrder = 1, Parent = card })
	W.text({ Size = UDim2.new(1, 0, 0, 44), Font = Theme.fontBlack, TextSize = 40, TextXAlignment = Enum.TextXAlignment.Center, Text = tostring(p.level), LayoutOrder = 2, Parent = card })
	local order = 3
	for _, r in p.rewards do
		local text = `Lv {r.level}: +{Format.compact(r.coins)} coins, +{r.skillPoints} skill point`
		W.text({ Size = UDim2.new(1, 0, 0, 18), TextSize = 13, TextColor3 = C.sub, TextXAlignment = Enum.TextXAlignment.Center, Text = text, LayoutOrder = order, Parent = card })
		order += 1
		if r.text then
			W.text({ Size = UDim2.new(1, 0, 0, 18), Font = Theme.fontBold, TextSize = 13, TextColor3 = C.good, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Text = r.text, LayoutOrder = order, Parent = card })
			order += 1
		end
		if r.boosters then
			for id, n in r.boosters do
				local def = BoosterConfig.Defs[id]
				if def then
					W.text({ Size = UDim2.new(1, 0, 0, 18), TextSize = 13, TextColor3 = def.color, TextXAlignment = Enum.TextXAlignment.Center, Text = `Reward: {n}x {def.name}`, LayoutOrder = order, Parent = card })
					order += 1
				end
			end
		end
	end
	card.Position = UDim2.new(0.5, 0, 0, 60)
	TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0, 90) }):Play()
	tweenOut(card, 4.2, 0.6)
end

local function banner(title: string, subtitle: string, color: Color3)
	local card = W.card({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 90), Size = UDim2.fromOffset(420, 70), ZIndex = 30, Parent = root })
	local stroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Color = color
	stroke.Thickness = 2.5
	W.text({ Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 6), Font = Theme.fontBlack, TextSize = 26, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Center, Text = title, Parent = card })
	W.text({ Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 42), TextSize = 14, TextColor3 = C.sub, TextXAlignment = Enum.TextXAlignment.Center, Text = subtitle, Parent = card })
	tweenOut(card, 3.2, 0.6)
end

-- Dock fishing: a small card while a line is in the water (waiting, then the bite with a shrinking reel window) and toasts for the outcome.
local fishCard: Frame? = nil
local fishToken = 0

local function hideFishCard()
	fishToken += 1
	if fishCard then
		fishCard:Destroy()
		fishCard = nil
	end
end

local function showFishCard(title: string, text: string, color: Color3, window: number?)
	hideFishCard()
	local card = W.card({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 150), Size = UDim2.fromOffset(340, 64), ZIndex = 20, Parent = root })
	local stroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Color = color
	stroke.Thickness = 2.5
	W.text({ Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 4), Font = Theme.fontBlack, TextSize = 22, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Center, Text = title, Parent = card })
	W.text({ Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 34), TextSize = 13, TextColor3 = C.sub, TextXAlignment = Enum.TextXAlignment.Center, Text = text, Parent = card })
	fishCard = card
	local token = fishToken
	if window then
		local bar = W.frame({ Size = UDim2.new(1, -16, 0, 5), Position = UDim2.new(0, 8, 1, -9), BackgroundColor3 = color, BackgroundTransparency = 0, Parent = card })
		TweenService:Create(bar, TweenInfo.new(window, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 5) }):Play()
	end
	task.delay(if window then window + 0.3 else 50, function()
		if fishToken == token then
			hideFishCard()
		end
	end)
end

local function onFishing(p: any)
	local phase = p.phase
	if phase == "cast" then
		EffectsController.sound("Click", nil, 1, 0.8)
		showFishCard("LINE CAST", "Wait for a bite...", C.sub, nil)
	elseif phase == "bite" then
		EffectsController.sound("Spawn", nil, 1, 1)
		showFishCard("FISH ON!", "Press E / tap to reel it in!", C.warn, p.window)
	elseif phase == "early" then
		hideFishCard()
		Notifications.toast("Too early! You spooked the fish.", "warn")
	elseif phase == "missed" then
		hideFishCard()
		Notifications.toast("It got away...", "warn")
	elseif phase == "catch" then
		hideFishCard()
		EffectsController.sound("Coin", nil, 1, 1)
		Notifications.toast(`{p.name}! +{Format.compact(p.coins)} coins, +{Format.compact(p.xp)} XP`, "good")
		if p.sail then
			local flash = W.frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(150, 230, 250), BackgroundTransparency = 1, ZIndex = 40, Parent = root })
			TweenService:Create(flash, TweenInfo.new(1.3), { BackgroundTransparency = 0.1 }):Play()
			task.delay(2.2, function()
				TweenService:Create(flash, TweenInfo.new(1.4), { BackgroundTransparency = 1 }):Play()
				task.delay(1.5, function()
					flash:Destroy()
				end)
			end)
			banner("THE TIDE PULLS YOU OUT", "Hold on tight...", Color3.fromRGB(110, 220, 240))
		end
	end
end

local function onGuardianVictory(p: any)
	local flash = W.frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 232, 170), BackgroundTransparency = 0.35, ZIndex = 40, Parent = root })
	TweenService:Create(flash, TweenInfo.new(1.2), { BackgroundTransparency = 1 }):Play()
	task.delay(1.3, function()
		flash:Destroy()
	end)
	EffectsController.sound("LevelUp", nil, 1, 0.8)
	CameraController.shake(0.4, 0.5)
	local detail
	if p.next and #p.nextMissing == 0 then
		detail = `{p.nextName} can now be unlocked at a Skyport.`
	elseif p.next then
		detail = `Next: {p.nextName}. Still needed: {table.concat(p.nextMissing, ", ")}`
	else
		detail = "More islands are coming."
	end
	banner(`{string.upper(p.name)} DEFEATED`, detail, C.shard)
end

local function onRebirth(p: any)
	local flash = W.frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0, ZIndex = 40, Parent = root })
	TweenService:Create(flash, TweenInfo.new(1.6), { BackgroundTransparency = 1 }):Play()
	task.delay(1.7, function()
		flash:Destroy()
	end)
	banner(`REBIRTH {p.rebirths}`, "Your arms remember everything. Climb again, stronger.", C.shard)
end

function Notifications.start(uiRoot: Frame)
	root = uiRoot
	toastHolder = W.frame({ Name = "Toasts", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 86), Size = UDim2.fromOffset(500, 120), Parent = root })
	W.list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center).Parent = toastHolder
	feed = W.frame({ Name = "Feed", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -88), Size = UDim2.fromOffset(260, 110), Parent = root })
	local layout = W.list(Enum.FillDirection.Vertical, 2)
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Parent = feed

	local remotes = Net.client()
	remotes.Notify.OnClientEvent:Connect(function(kind: string, p: any)
		if kind == "Reward" then
			onReward(p)
		elseif kind == "LevelUp" then
			onLevelUp(p)
		elseif kind == "Toast" then
			Notifications.toast(p.text, p.kind)
		elseif kind == "Island" then
			banner(string.upper(p.name), p.tagline, C.accent)
		elseif kind == "Fishing" then
			onFishing(p)
		elseif kind == "Rebirth" then
			onRebirth(p)
		elseif kind == "CreatureReward" then
			onCreatureReward(p)
		elseif kind == "GuardianVictory" then
			onGuardianVictory(p)
		end
	end)
end

return Notifications
