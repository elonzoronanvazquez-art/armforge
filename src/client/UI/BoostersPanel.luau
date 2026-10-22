--!strict
-- BOOSTERS: owned boosters (activate one to start its timer) and the ones currently running. Same-stat boosters add
-- up (capped); re-activating extends the timer up to its maximum.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local BoosterConfig = require(Shared.Config.Boosters)
local Format = require(Shared.Util.Format)
local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local W = require(script.Parent.Widgets)
local Messages = require(script.Parent.Messages)

local C = Theme.colors

local Panel = {}
Panel.name = "Boosters"
Panel.title = "BOOSTERS"
Panel.size = Vector2.new(700, 440)

local cards: { [string]: any } = {}
local refs: { [string]: any } = {}

function Panel.refresh()
	local d = Store.data
	if not d then
		return
	end
	local any = false
	for _, id in BoosterConfig.Order do
		local def = BoosterConfig.Defs[id]
		local c = cards[id]
		local count = d.boosters.inventory[id] or 0
		local left = Store.boosterRemaining(id)
		c.count.Text = `x{count}`
		c.count.TextColor3 = if count > 0 then C.text else C.dim
		if left > 0 then
			any = true
			c.bar.set(left / def.maxDuration, `ACTIVE  {Format.clock(left)}`)
			c.bar.root.Visible = true
		else
			c.bar.root.Visible = false
		end
		local atMax = left >= def.maxDuration - 0.5
		W.setEnabled(c.button, count > 0 and not atMax)
		c.button.Text = if atMax then "AT MAX" elseif left > 0 then `EXTEND  +{Format.clock(def.duration)}` else `ACTIVATE  {Format.clock(def.duration)}`
	end
	refs.note.Visible = not any
end

function Panel.build(content: Frame)
	W.text({
		Position = UDim2.fromOffset(18, 4),
		Size = UDim2.new(1, -36, 0, 34),
		TextWrapped = true,
		TextSize = 13,
		TextColor3 = C.sub,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "Boosters come from level milestones, rebirths and events. Boosters of the same type extend each other; different boosters of one stat add together up to a cap. Timers only run while you are playing.",
		Parent = content,
	})
	local list = W.scroll({ Position = UDim2.fromOffset(14, 44), Size = UDim2.new(1, -28, 1, -56), Parent = content })
	W.list(Enum.FillDirection.Vertical, 8).Parent = list
	for i, id in BoosterConfig.Order do
		local def = BoosterConfig.Defs[id]
		local card = W.card({ Size = UDim2.new(1, -8, 0, 64), LayoutOrder = i, Parent = list })
		W.padding(10, 8).Parent = card
		local swatch = W.frame({ Size = UDim2.fromOffset(6, 48), BackgroundColor3 = def.color, BackgroundTransparency = 0, Parent = card })
		W.corner(UDim.new(1, 0)).Parent = swatch
		W.text({ Position = UDim2.fromOffset(16, 0), Size = UDim2.new(0.5, 0, 0, 22), Font = Theme.fontBold, TextSize = 16, Text = def.name, Parent = card })
		W.text({ Position = UDim2.fromOffset(16, 22), Size = UDim2.new(0.55, 0, 0, 18), TextSize = 13, TextColor3 = C.sub, Text = def.blurb, Parent = card })
		local count = W.text({ Position = UDim2.new(1, -190, 0, 4), Size = UDim2.fromOffset(40, 24), Font = Theme.fontBlack, TextSize = 18, Text = "x0", Parent = card })
		local bar = W.bar({ Position = UDim2.fromOffset(16, 42), Size = UDim2.new(0.55, 0, 0, 14), color = def.color, textSize = 10, Parent = card })
		local button = W.button({
			Text = "ACTIVATE",
			Size = UDim2.fromOffset(150, 40),
			Position = UDim2.new(1, 0, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			textSize = 13,
			style = "primary",
			onClick = function()
				Messages.report(Store.request("ActivateBooster", { id = id }), `{def.name} activated`, "Upgrade")
			end,
			Parent = card,
		})
		cards[id] = { count = count, bar = bar, button = button }
	end
	refs.note = W.text({ Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 99, TextSize = 12, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Center, Text = "No boosters are running.", Parent = list })
end

return Panel
