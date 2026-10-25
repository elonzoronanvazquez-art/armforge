--!strict
-- DEVELOPER: the in-game test kit (coins, XP, levels, islands, teleports, god mode...). Only usable by players the server authorizes
-- (Services/DevAccess); everyone else never sees the DEV button, and the server refuses their requests anyway. Every button is just a
-- command line sent to the server (`Request "Dev"`), so the command box and the buttons do exactly the same thing. See docs/DEV_MODE.md.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local IslandConfig = require(Shared.Config.Islands)
local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local W = require(script.Parent.Widgets)
local Notifications = require(script.Parent.Notifications)

local C = Theme.colors

local Panel = {}
Panel.name = "Dev"
Panel.title = "DEVELOPER MODE"
Panel.size = Vector2.new(800, 560)

local refs: { [string]: any } = {}
local resetArmedAt = 0

-- Sends a command line and shows what the server said.
local function run(line: string)
	if line == "" then
		return
	end
	local result = Store.request("Dev", { line = line })
	local text = if result and result.msg then tostring(result.msg) else "no answer from the server"
	refs.output.Text = (if result and result.ok then "OK  " else "NO  ") .. text
	refs.output.TextColor3 = if result and result.ok then C.good else C.bad
	if result and result.ok then
		Notifications.toast(text, "good")
	end
end

local function section(parent: Instance, order: number, title: string, items: { { label: string, cmd: any, style: string? } })
	local box = W.frame({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, Parent = parent })
	W.list(Enum.FillDirection.Vertical, 4).Parent = box
	W.text({ Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 1, Font = Theme.fontBold, TextSize = 12, TextColor3 = C.accent, Text = title, Parent = box })
	local grid = W.frame({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Parent = box })
	W.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(176, 32),
		CellPadding = UDim2.fromOffset(6, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}).Parent = grid
	for i, item in items do
		W.button({
			Text = item.label,
			textSize = 12,
			style = item.style or "ghost",
			LayoutOrder = i,
			onClick = function()
				local cmd = item.cmd
				if type(cmd) == "function" then
					cmd = (cmd :: any)()
				end
				if type(cmd) == "string" then
					run(cmd)
				end
			end,
			Parent = grid,
		})
	end
end

function Panel.build(content: Frame)
	-- command line
	local bar = W.frame({ Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -32, 0, 34), Parent = content })
	local box = W.new("TextBox", {
		Size = UDim2.new(1, -92, 1, 0),
		BackgroundColor3 = C.panelLo,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		PlaceholderText = "type a command: coins 5000, level 40, goto Dustwake, kit, help",
		PlaceholderColor3 = C.dim,
		Text = "",
		TextColor3 = C.text,
		TextSize = 14,
		Font = Theme.fontBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = bar,
	})
	W.corner(UDim.new(0, 8)).Parent = box
	W.stroke(C.stroke, 1, 0.3).Parent = box
	W.padding(10, 0).Parent = box
	refs.box = box
	W.button({
		Text = "RUN",
		Size = UDim2.fromOffset(84, 34),
		Position = UDim2.new(1, 0, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		textSize = 13,
		style = "primary",
		onClick = function()
			run(box.Text)
			box.Text = ""
		end,
		Parent = bar,
	})
	box.FocusLost:Connect(function(enter: boolean)
		if enter then
			run(box.Text)
			box.Text = ""
			box:CaptureFocus()
		end
	end)
	refs.output = W.text({
		Position = UDim2.fromOffset(16, 46),
		Size = UDim2.new(1, -32, 0, 34),
		TextSize = 12,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = C.sub,
		Text = "Every button below sends a command; `help` lists them all. Changes are real: they are saved with your profile.",
		Parent = content,
	})

	local scroll = W.scroll({ Position = UDim2.fromOffset(16, 84), Size = UDim2.new(1, -32, 1, -96), Parent = content })
	W.list(Enum.FillDirection.Vertical, 10).Parent = scroll
	W.padding(2, 2).Parent = scroll

	section(scroll, 1, "RESOURCES", {
		{ label = "+1K coins", cmd = "coins 1000" },
		{ label = "+1M coins", cmd = "coins 1000000" },
		{ label = "+1B coins", cmd = "coins 1000000000" },
		{ label = "+100 shards", cmd = "shards 100" },
		{ label = "+10K XP", cmd = "xp 10000" },
		{ label = "+1M XP", cmd = "xp 1000000" },
		{ label = "Level 12", cmd = "level 12" },
		{ label = "Level 25", cmd = "level 25" },
		{ label = "Level 40 (max)", cmd = "level 40" },
		{
			label = "Rebirth +1",
			cmd = function()
				local d = Store.data
				return `rebirths {if d then d.rebirths + 1 else 1}`
			end,
		},
		{ label = "Rebirths = 6", cmd = "rebirths 6" },
		{ label = "Rebirths = 0", cmd = "rebirths 0" },
	})
	section(scroll, 2, "PROGRESS", {
		{ label = "UNLOCK ALL ISLANDS", cmd = "unlockislands", style = "primary" },
		{ label = "Complete guardians", cmd = "completeguardians" },
		{ label = "Unlock all arms", cmd = "unlockarms" },
		{ label = "Max all arms", cmd = "maxarms" },
		{ label = "Equip Void arms", cmd = "equip void" },
		{ label = "Max all skills", cmd = "skills" },
		{ label = "Boosters x3", cmd = "boosters 3" },
		{ label = "FULL TEST KIT", cmd = "kit", style = "good" },
	})
	local islands = {}
	for _, id in IslandConfig.Order do
		local def = IslandConfig.Defs[id]
		if not def.comingSoon then
			table.insert(islands, { label = "Go: " .. def.name, cmd = "goto " .. id })
		end
	end
	table.insert(islands, { label = "Go: The Atlantic Sea", cmd = "goto AtlanticSea" })
	table.insert(islands, { label = "Go: The Canopy Grove", cmd = "goto CanopyGrove" })
	table.insert(islands, { label = "Sail / climb home", cmd = "home" })
	table.insert(islands, { label = "Go to this island's seal", cmd = "seal" })
	section(scroll, 3, "TELEPORT (opens the island)", islands)
	section(scroll, 4, "PLAYER", {
		{ label = "God mode (toggle)", cmd = "god" },
		{ label = "Damage x100", cmd = "power 100" },
		{ label = "Damage x1000000", cmd = "power 1000000" },
		{ label = "Damage normal", cmd = "power 1" },
		{ label = "Speed 60", cmd = "speed 60" },
		{ label = "Speed normal", cmd = "speed 0" },
		{ label = "Heal", cmd = "heal" },
		{ label = "Reset cooldowns", cmd = "resetcd" },
		{ label = "Summit Momentum", cmd = "momentum" },
	})
	local dangerous = W.frame({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 5, Parent = scroll })
	W.list(Enum.FillDirection.Vertical, 4).Parent = dangerous
	W.text({ Size = UDim2.new(1, 0, 0, 18), Font = Theme.fontBold, TextSize = 12, TextColor3 = C.bad, Text = "DANGER", Parent = dangerous })
	refs.reset = W.button({
		Text = "Reset profile to a new player",
		Size = UDim2.fromOffset(260, 32),
		textSize = 12,
		style = "danger",
		onClick = function()
			-- two clicks within three seconds: this wipes the saved progress
			if os.clock() - resetArmedAt < 3 then
				resetArmedAt = 0
				refs.reset.Text = "Reset profile to a new player"
				run("reset confirm")
			else
				resetArmedAt = os.clock()
				refs.reset.Text = "CLICK AGAIN TO WIPE EVERYTHING"
				task.delay(3, function()
					if refs.reset and resetArmedAt ~= 0 and os.clock() - resetArmedAt >= 3 then
						resetArmedAt = 0
						refs.reset.Text = "Reset profile to a new player"
					end
				end)
			end
		end,
		LayoutOrder = 2,
		Parent = dangerous,
	})
end

function Panel.refresh() end

return Panel
