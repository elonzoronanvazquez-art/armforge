--!strict
-- ISLANDS: the progression ladder. Shows each island's requirements (level / rebirth) and lets the player unlock and
-- travel, which the server only allows at a Skyport terminal and only when the same checks (shared/Logic/Islands) pass.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local IslandConfig = require(Shared.Config.Islands)
local RockConfig = require(Shared.Config.Rocks)
local IslandLogic = require(Shared.Logic.Islands)
local Guardians = require(Shared.Logic.Guardians)
local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local W = require(script.Parent.Widgets)
local Messages = require(script.Parent.Messages)
local UI = require(script.Parent.UI)

local C = Theme.colors

local Panel = {}
Panel.name = "Islands"
Panel.title = "ISLANDS"
Panel.size = Vector2.new(900, 520)

local cards: { [string]: any } = {}
local refs: { [string]: any } = {}

local function nearSkyport(): boolean
	local char = Players.LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return false
	end
	for _, inst in CollectionService:GetTagged("Skyport") do
		if inst:IsA("BasePart") and (inst.Position - hrp.Position).Magnitude <= 60 then
			return true
		end
	end
	return false
end

function Panel.refresh()
	local d = Store.data
	if not d then
		return
	end
	local near = nearSkyport()
	refs.banner.Text = if near then "Skyport terminal in range: you can unlock and travel." else "Walk to a Skyport terminal to unlock islands and travel between them."
	refs.banner.TextColor3 = if near then C.good else C.warn
	for _, id in IslandConfig.Order do
		local card = cards[id]
		local status = IslandLogic.status(d, id)
		local here = d.islands.current == id
		if status.comingSoon then
			card.state.Text = "COMING SOON"
			card.state.BackgroundColor3 = C.dim
		elseif status.unlocked then
			card.state.Text = if here then "YOU ARE HERE" else "UNLOCKED"
			card.state.BackgroundColor3 = if here then C.accent else C.good
		else
			card.state.Text = "LOCKED"
			card.state.BackgroundColor3 = C.bad
		end
		for _, child in card.reqs:GetChildren() do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		local n = 0
		local function req(text: string, met: boolean)
			n += 1
			W.text({ Size = UDim2.new(1, 0, 0, 16), LayoutOrder = n, TextSize = 12, TextColor3 = if met then C.good else C.bad, Text = (if met then "OK    " else "NEED  ") .. text, Parent = card.reqs })
		end
		for _, r in IslandLogic.requirements(d, id) do
			req(r.text, r.met)
		end
		if n == 0 then
			W.text({ Size = UDim2.new(1, 0, 0, 16), TextSize = 12, TextColor3 = C.sub, Text = "Open to everyone", Parent = card.reqs })
		end
		-- this island's own guardian, and what its defeat does for the island behind it
		local gate = Guardians.gate(d, id, IslandLogic.missing)
		local guard = card.guardian :: TextLabel
		if gate.state == "no_guardian" then
			guard.Text = "GUARDIAN\nNot yet awake."
			guard.TextColor3 = C.dim
		elseif gate.state == "rebirth_needed" then
			guard.Text = `GUARDIAN: {gate.guardianName}\nSealed. Needs Rebirth {gate.rebirthsNeeded} (you have {gate.rebirthsHave}).`
			guard.TextColor3 = C.bad
		elseif gate.state == "ready" then
			guard.Text = `GUARDIAN: {gate.guardianName}\nThe seal will open for you. Break it and fight!`
			guard.TextColor3 = C.warn
		else
			local nextText = ""
			if gate.next then
				local nextName = IslandConfig.Defs[gate.next].name
				if gate.nextState == "unlocked" then
					nextText = `\n{nextName} is open.`
				elseif gate.nextState == "available" then
					nextText = `\n{nextName} can be unlocked now!`
				elseif gate.nextState == "locked" then
					nextText = `\n{nextName} still needs: {table.concat(gate.nextMissing, ", ")}`
				end
			end
			guard.Text = `GUARDIAN DEFEATED: {gate.guardianName}{nextText}`
			guard.TextColor3 = C.good
		end
		local btn = card.button
		if status.comingSoon then
			btn.Text = "UNDER CONSTRUCTION"
			W.setEnabled(btn, false)
		elseif status.unlocked then
			btn.Text = if here then "ALREADY HERE" else "TRAVEL"
			W.setEnabled(btn, near and not here)
		else
			btn.Text = if status.canUnlock then "UNLOCK ISLAND" else "REQUIREMENTS NOT MET"
			W.setEnabled(btn, near and status.canUnlock)
		end
	end
end

function Panel.build(content: Frame)
	refs.banner = W.text({ Position = UDim2.fromOffset(18, 4), Size = UDim2.new(1, -36, 0, 20), Font = Theme.fontBold, TextSize = 13, Text = "", Parent = content })
	-- seven islands do not fit side by side: the row scrolls sideways
	local row = W.scroll({
		Position = UDim2.fromOffset(14, 30),
		Size = UDim2.new(1, -28, 1, -42),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 6,
		Parent = content,
	})
	W.list(Enum.FillDirection.Horizontal, 8).Parent = row
	for i, id in IslandConfig.Order do
		local def = IslandConfig.Defs[id]
		local card = W.card({ Size = UDim2.new(0, 196, 1, -12), LayoutOrder = i, Parent = row })
		W.padding(10, 10).Parent = card
		local stroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke
		stroke.Color = def.accent
		stroke.Transparency = 0.3
		local banner = W.frame({ Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = def.accent, BackgroundTransparency = 0, Parent = card })
		W.corner(UDim.new(0, 8)).Parent = banner
		local grad = Instance.new("UIGradient")
		grad.Color = ColorSequence.new(def.sky, def.accent)
		grad.Rotation = 90
		grad.Parent = banner
		W.text({ Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Font = Theme.fontBlack, TextSize = 28, TextColor3 = C.black, TextTransparency = 0.25, Text = tostring(def.order), Parent = banner })
		W.text({ Position = UDim2.fromOffset(0, 62), Size = UDim2.new(1, 0, 0, 36), Font = Theme.fontBlack, TextSize = 15, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Text = def.name, Parent = card })
		local state = W.pill("", C.good, C.black, { Position = UDim2.fromOffset(0, 98), Parent = card })
		W.text({ Position = UDim2.fromOffset(0, 120), Size = UDim2.new(1, 0, 0, 74), TextWrapped = true, TextSize = 11, TextColor3 = C.sub, TextYAlignment = Enum.TextYAlignment.Top, Text = def.description, Parent = card })
		local boostText = IslandLogic.boostText(id)
		if boostText then
			W.text({ Position = UDim2.fromOffset(0, 194), Size = UDim2.new(1, 0, 0, 16), TextSize = 12, Font = Theme.fontBold, TextColor3 = C.good, Text = `BOOST  {boostText}`, Parent = card })
		end
		local reqs = W.frame({ Position = UDim2.fromOffset(0, 214), Size = UDim2.new(1, 0, 0, 50), Parent = card })
		W.list(Enum.FillDirection.Vertical, 1).Parent = reqs
		local rockNames = {}
		for _, field in def.fields do
			for _, entry in field.rocks do
				local name = RockConfig.Defs[entry.rock].name
				if not table.find(rockNames, name) then
					table.insert(rockNames, name)
				end
			end
		end
		W.text({ Position = UDim2.fromOffset(0, 266), Size = UDim2.new(1, 0, 0, 40), TextWrapped = true, TextSize = 10, TextColor3 = C.dim, TextYAlignment = Enum.TextYAlignment.Top, Text = if #rockNames > 0 then "Rocks: " .. table.concat(rockNames, ", ") else "Rocks: unknown", Parent = card })
		local guardianText = W.text({ Position = UDim2.fromOffset(0, 308), Size = UDim2.new(1, 0, 0, 78), TextWrapped = true, TextSize = 11, Font = Theme.fontBold, TextColor3 = C.sub, TextYAlignment = Enum.TextYAlignment.Top, Text = "", Parent = card })
		local button = W.button({
			Text = "",
			Size = UDim2.new(1, 0, 0, 36),
			Position = UDim2.new(0, 0, 1, 0),
			AnchorPoint = Vector2.new(0, 1),
			textSize = 12,
			style = "primary",
			onClick = function()
				local d = Store.data
				local status = IslandLogic.status(d, id)
				if status.unlocked then
					local result = Store.request("Travel", { islandId = id })
					if Messages.report(result, nil, "Equip") then
						UI.close()
					end
				else
					Messages.report(Store.request("UnlockIsland", { islandId = id }), `{def.name} unlocked!`, "Upgrade")
				end
			end,
			Parent = card,
		})
		cards[id] = { state = state, reqs = reqs, button = button, guardian = guardianText }
	end
end

return Panel
