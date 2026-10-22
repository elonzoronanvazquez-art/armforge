--!strict
-- THE ARMORY: the arm collection. Left: every arm set with its state (equipped / owned / buyable / locked). Right: a live
-- 3D preview, stats, upgrade / equip / buy, and the Style tab (palette, finish, trail, glow cosmetics).
-- Every button calls a server-validated request; this panel only displays state from the Store.

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local Arms = require(Shared.Config.Arms)
local Cosmetics = require(Shared.Config.Cosmetics)
local Equipment = require(Shared.Logic.Equipment)
local Formulas = require(Shared.Logic.Formulas)
local ArmBuilder = require(Shared.Runtime.ArmBuilder)
local Format = require(Shared.Util.Format)
local IslandConfig = require(Shared.Config.Islands)
local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local W = require(script.Parent.Widgets)
local Messages = require(script.Parent.Messages)

local C = Theme.colors

local Panel = {}
Panel.name = "Arms"
Panel.title = "THE ARMORY"
Panel.size = Vector2.new(800, 520)

local selected: string = Arms.StarterId
local tab = "details"
local rows: { [string]: { frame: Frame, stroke: UIStroke, state: TextLabel, level: TextLabel } } = {}
local viewport: ViewportFrame
local viewModel: Model? = nil
local viewKey = ""
local spin = 0
local connection: RBXScriptConnection? = nil
local previewCam: Camera

local refs: { [string]: any } = {}

-- Preview ------------------------------------------------------------------------------------------------------------

local function recipeFor(armId: string): ArmBuilder.Recipe
	local d = Store.data
	if d and d.arms.owned[armId] then
		return Equipment.visualRecipe(d, armId)
	end
	local r = ArmBuilder.defaultRecipe(armId)
	r.tier = 2
	return r
end

local function rebuildPreview()
	local recipe = recipeFor(selected)
	local key = `{selected}:{recipe.tier}:{recipe.primary}:{recipe.glow}:{recipe.material.Name}:{recipe.glowScale}`
	if key == viewKey then
		return
	end
	viewKey = key
	if viewModel then
		viewModel:Destroy()
	end
	local model = ArmBuilder.buildDisplay(recipe, "R")
	model.PrimaryPart = model:FindFirstChild("UpperArm") :: BasePart
	model.Parent = viewport
	viewModel = model
end

local function startSpin()
	if connection then
		return
	end
	connection = RunService.RenderStepped:Connect(function(dt: number)
		spin += dt * 0.7
		if viewModel and viewModel.PrimaryPart then
			viewModel:PivotTo(CFrame.new(0, -1.2, 0) * CFrame.Angles(0, spin, 0) * CFrame.new(0, 1.2, 0))
		end
	end)
end

local function stopSpin()
	if connection then
		connection:Disconnect()
		connection = nil
	end
end

-- Helpers ------------------------------------------------------------------------------------------------------------

local function stateOf(armId: string): (string, Color3)
	local d = Store.data
	if not d then
		return "", C.dim
	end
	if d.arms.equipped == armId then
		return "EQUIPPED", C.good
	elseif d.arms.owned[armId] then
		return "OWNED", C.sub
	elseif Equipment.purchaseBlocker(d, armId) == nil then
		return "AVAILABLE", C.accent
	end
	return "LOCKED", C.dim
end

local function statRow(parent: Instance, order: number, label: string, value: string, color: Color3?)
	local row = W.frame({ Size = UDim2.new(0.5, -4, 0, 20), LayoutOrder = order, Parent = parent })
	W.text({ Size = UDim2.new(0.5, 0, 1, 0), TextColor3 = C.sub, TextSize = 13, Text = label, Parent = row })
	W.text({ Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.fromScale(0.5, 0), Font = Theme.fontBold, TextSize = 13, TextColor3 = color or C.text, Text = value, Parent = row })
end

local function reqLine(parent: Instance, order: number, text: string, met: boolean)
	local l = W.text({
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = order,
		TextSize = 13,
		TextColor3 = if met then C.good else C.bad,
		Text = (if met then "OK    " else "NEED  ") .. text,
		Parent = parent,
	})
	return l
end

local function request(action: string, args: any, success: string?, sound: string?)
	local result = Store.request(action, args)
	Messages.report(result, success, sound)
end

-- Detail tab ----------------------------------------------------------------------------------------------------------

local function buildDetails(parent: Instance)
	local d = Store.data
	local def = Arms.Defs[selected]
	local owned = d.arms.owned[selected] == true
	local level = d.arms.levels[selected] or 0
	local list = W.frame({ Name = "Details", Size = UDim2.new(1, 0, 1, 0), Parent = parent })
	W.list(Enum.FillDirection.Vertical, 6).Parent = list

	local stats = W.frame({ Size = UDim2.new(1, 0, 0, 66), LayoutOrder = 1, Parent = list })
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -4, 0, 20)
	grid.CellPadding = UDim2.fromOffset(8, 0)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = stats
	local power = Formulas.armPower(selected, level)
	statRow(stats, 1, "Power", Format.compact(power) .. (if level < def.maxLevel then `  (next: {Format.compact(Formulas.armPower(selected, level + 1))})` else ""), C.accent)
	statRow(stats, 2, "Strike time", string.format("%.2fs", def.cooldown))
	statRow(stats, 3, "Crit chance", Format.percent(def.critChance) .. ` x{def.critMult}`)
	statRow(stats, 4, "Reach", `{def.reach} studs`)
	statRow(stats, 5, "Armor pierce", Format.percent(def.pierce))
	statRow(stats, 6, "Coin bonus", if def.coinBonus > 0 then "+" .. Format.percent(def.coinBonus) else "-")

	W.text({ Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 2, TextWrapped = true, TextSize = 13, TextColor3 = C.accent, TextYAlignment = Enum.TextYAlignment.Top, Font = Theme.fontBold, Text = def.traitText, Parent = list })

	if owned then
		local nextCost = Formulas.upgradeCost(selected, level)
		local row = W.frame({ Name = "Actions", Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 3, Parent = list })
		W.list(Enum.FillDirection.Horizontal, 8).Parent = row
		local isEq = d.arms.equipped == selected
		W.button({
			Name = "EquipButton",
			Text = if isEq then "EQUIPPED" else "EQUIP",
			Size = UDim2.new(0.4, -4, 1, 0),
			style = if isEq then "ghost" else "primary",
			enabled = not isEq,
			onClick = function()
				request("Equip", { armId = selected }, `Equipped {def.name}`, "Equip")
			end,
			Parent = row,
		})
		local label = if nextCost then `UPGRADE  {Format.compact(nextCost)}` else "MAX LEVEL"
		W.button({
			Name = "UpgradeButton",
			Text = label,
			Size = UDim2.new(0.6, -4, 1, 0),
			style = if nextCost and d.coins >= nextCost then "good" else "ghost",
			enabled = nextCost ~= nil,
			onClick = function()
				request("UpgradeArm", { armId = selected }, nil, "Upgrade")
			end,
			Parent = row,
		})
		W.text({ Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 4, TextSize = 12, TextColor3 = C.sub, Text = `Upgrade level {level}/{def.maxLevel}. Visual tiers unlock at levels {table.concat(Arms.VisualTierLevels, ", ")}.`, Parent = list })
	else
		local req = def.requires
		local lines = W.frame({ Size = UDim2.new(1, 0, 0, 80), LayoutOrder = 3, Parent = list })
		W.list(Enum.FillDirection.Vertical, 2).Parent = lines
		local n = 0
		local function add(text: string, met: boolean)
			n += 1
			reqLine(lines, n, text, met)
		end
		if req.level then
			add(`Level {req.level}`, d.level >= req.level)
		end
		if req.rebirths then
			add(`Rebirth {req.rebirths}`, d.rebirths >= req.rebirths)
		end
		if req.island then
			add(`Unlock {IslandConfig.Defs[req.island].name}`, d.islands.unlocked[req.island] == true)
		end
		if (def.cost.coins or 0) > 0 then
			add(`{Format.commas(def.cost.coins :: number)} coins`, d.coins >= (def.cost.coins :: number))
		end
		if (def.cost.shards or 0) > 0 then
			add(`{def.cost.shards} Forge Shards`, d.shards >= (def.cost.shards :: number))
		end
		local blocker = Equipment.purchaseBlocker(d, selected)
		W.button({
			Name = "BuyButton",
			Text = if blocker == nil then "BUY ARMS" else "LOCKED",
			Size = UDim2.new(1, 0, 0, 44),
			LayoutOrder = 4,
			style = if blocker == nil then "primary" else "ghost",
			enabled = blocker == nil,
			onClick = function()
				request("BuyArm", { armId = selected }, `Unlocked {def.name}!`, "Equip")
			end,
			Parent = list,
		})
	end
end

-- Style tab ------------------------------------------------------------------------------------------------------------------

local function chipRow(parent: Instance, order: number, title: string, kind: string, ids: { string }, current: string)
	local d = Store.data
	local group = (Cosmetics.Kinds :: any)[kind]
	local box = W.frame({ Size = UDim2.new(1, 0, 0, 46), LayoutOrder = order, Parent = parent })
	W.text({ Size = UDim2.new(1, 0, 0, 14), TextSize = 12, Font = Theme.fontBold, TextColor3 = C.sub, Text = string.upper(title), Parent = box })
	local row = W.frame({ Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, 0, 0, 28), Parent = box })
	W.list(Enum.FillDirection.Horizontal, 5).Parent = row
	for _, id in ids do
		local entry = group[id]
		local owned = Equipment.ownsCosmetic(d, kind, id)
		local active = current == id
		local text = if active then entry.name else if owned then entry.name else `{entry.name} · {Format.compact(entry.cost)}`
		local btn = W.button({
			Text = text,
			Size = UDim2.fromOffset(0, 28),
			textSize = 11,
			style = if active then "primary" elseif owned then "ghost" else "ghost",
			onClick = function()
				if not owned then
					local bought = Store.request("BuyCosmetic", { kind = kind, id = id })
					if not Messages.report(bought, nil, "Upgrade") then
						return
					end
				end
				request("SetCosmetic", { armId = selected, kind = kind, id = id }, nil, "Equip")
			end,
			Parent = row,
		})
		btn.AutomaticSize = Enum.AutomaticSize.X
		W.padding(10, 0).Parent = btn
		if kind == "palette" and entry.primary then
			-- a colour swatch makes palettes recognisable at a glance
			local sw = W.frame({ Size = UDim2.fromOffset(10, 10), Position = UDim2.new(0, 4, 0.5, -5), BackgroundColor3 = entry.glow or entry.primary, BackgroundTransparency = 0, Parent = btn })
			W.corner(UDim.new(1, 0)).Parent = sw
			;(btn :: any).TextXAlignment = Enum.TextXAlignment.Right
		end
	end
end

local function buildStyle(parent: Instance)
	local d = Store.data
	local list = W.frame({ Size = UDim2.new(1, 0, 1, 0), Parent = parent })
	W.list(Enum.FillDirection.Vertical, 4).Parent = list
	if not d.arms.owned[selected] then
		W.text({ Size = UDim2.new(1, 0, 0, 40), TextWrapped = true, TextColor3 = C.sub, TextSize = 14, Text = "Own this arm set to customise its look. Cosmetics never change power.", Parent = list })
		return
	end
	local sel = Equipment.selection(d, selected)
	chipRow(list, 1, "Palette", "palette", Cosmetics.PaletteOrder, sel.palette)
	chipRow(list, 2, "Finish", "finish", Cosmetics.FinishOrder, sel.finish)
	chipRow(list, 3, "Trail & impact colour", "trail", Cosmetics.TrailOrder, sel.trail)
	chipRow(list, 4, "Glow", "glow", Cosmetics.GlowOrder, sel.glow)
end

-- Layout -------------------------------------------------------------------------------------------------------------------------

local function refreshDetail()
	local d = Store.data
	if not d then
		return
	end
	local def = Arms.Defs[selected]
	local rc = Arms.Rarities[def.rarity].color
	refs.name.Text = def.name
	refs.rarity.Text = string.upper(def.rarity)
	refs.rarity.BackgroundColor3 = rc
	refs.identity.Text = def.identity
	refs.family.Text = `{def.family} family`
	for _, child in refs.body:GetChildren() do
		child:Destroy()
	end
	if tab == "details" then
		buildDetails(refs.body)
	else
		buildStyle(refs.body)
	end
	refs.tabDetails.BackgroundColor3 = if tab == "details" then C.accent else C.panelHi
	refs.tabStyle.BackgroundColor3 = if tab == "style" then C.accent else C.panelHi
	refs.tabDetails.TextColor3 = if tab == "details" then C.black else C.text
	refs.tabStyle.TextColor3 = if tab == "style" then C.black else C.text
	rebuildPreview()
end

function Panel.refresh()
	local d = Store.data
	if not d then
		return
	end
	for _, id in Arms.Order do
		local r = rows[id]
		if r then
			local state, color = stateOf(id)
			r.state.Text = state
			r.state.TextColor3 = color
			r.level.Text = if d.arms.owned[id] then `Lv {d.arms.levels[id] or 0}` else ""
			r.stroke.Color = if id == selected then C.accent else C.stroke
			r.stroke.Thickness = if id == selected then 2.5 else 1.2
			r.frame.BackgroundColor3 = if id == selected then C.panelHi else C.panel
		end
	end
	refreshDetail()
end

function Panel.build(content: Frame)
	-- left list
	local left = W.scroll({ Position = UDim2.fromOffset(14, 6), Size = UDim2.new(0, 290, 1, -18), Parent = content })
	W.list(Enum.FillDirection.Vertical, 6).Parent = left
	for i, id in Arms.Order do
		local def = Arms.Defs[id]
		local rc = Arms.Rarities[def.rarity].color
		local row = W.new("TextButton", {
			Size = UDim2.new(1, -8, 0, 62),
			BackgroundColor3 = C.panel,
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = i,
			Parent = left,
		})
		W.corner(UDim.new(0, 10)).Parent = row
		local stroke = W.stroke(C.stroke, 1.2)
		stroke.Parent = row
		local stripe = W.frame({ Size = UDim2.new(0, 5, 1, -14), Position = UDim2.fromOffset(6, 7), BackgroundColor3 = rc, BackgroundTransparency = 0, Parent = row })
		W.corner(UDim.new(1, 0)).Parent = stripe
		local badge = W.frame({ Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(20, 11), BackgroundColor3 = def.palette.primary, BackgroundTransparency = 0, Parent = row })
		W.corner(UDim.new(0, 8)).Parent = badge
		W.stroke(def.palette.glow, 2).Parent = badge
		W.text({ Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Font = Theme.fontBlack, TextSize = 20, TextColor3 = def.palette.glow, Text = string.sub(def.name, 1, 1), Parent = badge })
		W.text({ Position = UDim2.fromOffset(70, 8), Size = UDim2.new(1, -78, 0, 20), Font = Theme.fontBold, TextSize = 15, Text = def.name, Parent = row })
		local state = W.text({ Position = UDim2.fromOffset(70, 32), Size = UDim2.new(0, 100, 0, 18), Font = Theme.fontBold, TextSize = 11, Text = "", Parent = row })
		local level = W.text({ Position = UDim2.new(1, -10, 0, 32), AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(60, 18), TextXAlignment = Enum.TextXAlignment.Right, Font = Theme.fontBold, TextSize = 11, TextColor3 = C.accent, Text = "", Parent = row })
		row.Activated:Connect(function()
			selected = id
			tab = "details"
			Panel.refresh()
		end)
		rows[id] = { frame = row, stroke = stroke, state = state, level = level }
	end

	-- right column
	local right = W.frame({ Name = "Right", Position = UDim2.fromOffset(318, 6), Size = UDim2.new(1, -332, 1, -18), Parent = content })
	viewport = W.new("ViewportFrame", {
		Size = UDim2.new(1, 0, 0, 170),
		BackgroundColor3 = C.panelLo,
		BorderSizePixel = 0,
		Ambient = Color3.fromRGB(140, 130, 150),
		LightColor = Color3.fromRGB(255, 240, 220),
		LightDirection = Vector3.new(-1, -1.2, -1),
		Parent = right,
	})
	W.corner(UDim.new(0, 10)).Parent = viewport
	W.stroke(C.stroke, 1.2).Parent = viewport
	previewCam = Instance.new("Camera")
	previewCam.FieldOfView = 38
	previewCam.CFrame = CFrame.lookAt(Vector3.new(4.8, -1.6, 7.2), Vector3.new(0, -2.1, 0))
	previewCam.Parent = viewport
	viewport.CurrentCamera = previewCam

	refs.name = W.text({ Position = UDim2.fromOffset(0, 178), Size = UDim2.new(1, -110, 0, 26), Font = Theme.fontBlack, TextSize = 22, Text = "", Parent = right })
	refs.rarity = W.pill("", C.accent, C.black, { Position = UDim2.new(1, 0, 0, 182), AnchorPoint = Vector2.new(1, 0), Parent = right })
	refs.identity = W.text({ Position = UDim2.fromOffset(0, 204), Size = UDim2.new(1, 0, 0, 34), TextWrapped = true, TextSize = 13, TextColor3 = C.sub, TextYAlignment = Enum.TextYAlignment.Top, Text = "", Parent = right })
	refs.family = W.text({ Position = UDim2.new(1, 0, 0, 160), AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(160, 14), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 11, TextColor3 = C.dim, ZIndex = 5, Text = "", Parent = right })
	local tabs = W.frame({ Position = UDim2.fromOffset(0, 242), Size = UDim2.new(1, 0, 0, 28), Parent = right })
	W.list(Enum.FillDirection.Horizontal, 6).Parent = tabs
	refs.tabDetails = W.button({
		Text = "DETAILS",
		Size = UDim2.fromOffset(110, 28),
		textSize = 12,
		onClick = function()
			tab = "details"
			Panel.refresh()
		end,
		Parent = tabs,
	})
	refs.tabStyle = W.button({
		Text = "STYLE",
		Size = UDim2.fromOffset(110, 28),
		textSize = 12,
		onClick = function()
			tab = "style"
			Panel.refresh()
		end,
		Parent = tabs,
	})
	refs.body = W.frame({ Name = "Body", Position = UDim2.fromOffset(0, 278), Size = UDim2.new(1, 0, 1, -278), Parent = right })
end

function Panel.onOpen(_args: any)
	local d = Store.data
	if d and not rows[selected] then
		selected = d.arms.equipped
	end
	if d then
		selected = d.arms.equipped
	end
	tab = "details"
	startSpin()
end

function Panel.onClose()
	stopSpin()
end

return Panel
