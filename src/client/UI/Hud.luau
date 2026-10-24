--!strict
-- The always-on HUD: level / XP / currencies, boosters, target rock, tutorial hints, menu buttons, equipped arm, the
-- skill bar and a touch PUNCH button. Compact by design; everything else lives in panels.

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local Arms = require(Shared.Config.Arms)
local Rocks = require(Shared.Config.Rocks)
local SkillConfig = require(Shared.Config.Skills)
local BoosterConfig = require(Shared.Config.Boosters)
local ProgressionConfig = require(Shared.Config.Progression)
local Formulas = require(Shared.Logic.Formulas)
local Equipment = require(Shared.Logic.Equipment)
local Progression = require(Shared.Logic.Progression)
local Islands = require(Shared.Logic.Islands)
local IslandConfig = require(Shared.Config.Islands)
local Format = require(Shared.Util.Format)
local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local W = require(script.Parent.Widgets)
local UI = require(script.Parent.UI)
local TargetController = require(script.Parent.Parent.Controllers.TargetController)
local CombatController = require(script.Parent.Parent.Controllers.CombatController)

local C = Theme.colors

local Hud = {}

local refs: { [string]: any } = {}

local MENU = {
	{ id = "Arms", label = "ARMS", key = "F" },
	{ id = "Skills", label = "SKILLS", key = "K" },
	{ id = "Boosters", label = "BOOST", key = "B" },
	{ id = "Islands", label = "ISLES", key = "M" },
	{ id = "Rebirth", label = "REBIRTH", key = "R" },
	{ id = "Settings", label = "MENU", key = "O" },
}

-- Which menu buttons deserve a notification dot right now.
local function badges(): { [string]: boolean }
	local d = Store.data
	local out: { [string]: boolean } = {}
	if not d then
		return out
	end
	local armId: string = d.arms.equipped
	local cost = Formulas.upgradeCost(armId, d.arms.levels[armId] or 0)
	local shopping = false
	for _, id in Arms.Order do
		if Equipment.purchaseBlocker(d, id) == nil then
			shopping = true
		end
	end
	out.Arms = (cost ~= nil and d.coins >= cost) or shopping
	local learn = false
	if d.skillPoints > 0 then
		for _, id in SkillConfig.Order do
			local def = SkillConfig.Defs[id]
			local rank = d.skills.ranks[id] or 0
			if d.level >= def.unlockLevel and rank < def.maxRank and d.skillPoints >= def.rankCost[rank + 1] then
				learn = true
			end
		end
	end
	out.Skills = learn
	local boosters = false
	for _ in d.boosters.inventory do
		boosters = true
	end
	out.Boosters = boosters
	local isle = false
	for _, id in IslandConfig.Order do
		local st = Islands.status(d, id)
		if not st.unlocked and st.canUnlock then
			isle = true
		end
	end
	out.Islands = isle
	out.Rebirth = Progression.rebirthStatus(d).eligible
	return out
end

local function buildStatusCard(root: Frame)
	local card = W.card({ Name = "Status", Position = UDim2.fromOffset(14, 12), Size = UDim2.fromOffset(300, 108), Parent = root })
	W.padding(10).Parent = card
	local badge = W.frame({ Size = UDim2.fromOffset(46, 46), BackgroundColor3 = C.accent, BackgroundTransparency = 0, Parent = card })
	W.corner(UDim.new(1, 0)).Parent = badge
	W.stroke(Color3.fromRGB(255, 220, 170), 2).Parent = badge
	refs.levelText = W.text({
		Size = UDim2.fromScale(1, 1),
		Text = "1",
		Font = Theme.fontBlack,
		TextSize = 22,
		TextColor3 = C.black,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = badge,
	})
	refs.nameText = W.text({
		Position = UDim2.fromOffset(56, 0),
		Size = UDim2.new(1, -56, 0, 22),
		Text = "Forgemaster",
		Font = Theme.fontBold,
		TextSize = 16,
		Parent = card,
	})
	refs.rebirthPill = W.pill("", C.shard, C.black, { Position = UDim2.new(1, -4, 0, 2), AnchorPoint = Vector2.new(1, 0), Visible = false, Parent = card })
	refs.xpBar = W.bar({ Position = UDim2.fromOffset(56, 28), Size = UDim2.new(1, -56, 0, 16), color = C.xp, textSize = 11, Parent = card })
	local row = W.frame({ Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 0, 22), Parent = card })
	W.list(Enum.FillDirection.Horizontal, 14).Parent = row
	refs.coins = W.currency("coin", 22)
	refs.coins.root.Parent = row
	refs.shards = W.currency("shard", 22)
	refs.shards.root.Parent = row
	-- where the player is, and that biome's reward boost
	refs.islandText = W.text({ Position = UDim2.fromOffset(0, 82), Size = UDim2.new(1, 0, 0, 16), TextSize = 12, Font = Theme.fontBold, TextColor3 = C.sub, Text = "", Parent = card })
	-- booster chips under the card
	refs.boosterRow = W.frame({ Name = "Boosters", Position = UDim2.fromOffset(14, 126), Size = UDim2.fromOffset(300, 22), Parent = root })
	W.list(Enum.FillDirection.Horizontal, 6).Parent = refs.boosterRow
end

local function buildTargetCard(root: Frame)
	local card = W.card({
		Name = "Target",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(330, 66),
		Visible = false,
		Parent = root,
	})
	W.padding(10, 8).Parent = card
	refs.targetCard = card
	refs.targetName = W.text({ Size = UDim2.new(1, -90, 0, 20), Font = Theme.fontBold, TextSize = 16, Text = "Rock", Parent = card })
	refs.targetStage = W.text({
		Size = UDim2.new(0, 84, 0, 20),
		Position = UDim2.new(1, 0, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Theme.fontBold,
		TextSize = 12,
		TextColor3 = C.accent,
		Text = "INTACT",
		Parent = card,
	})
	refs.targetBar = W.bar({ Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 20), color = C.accent, textSize = 12, Parent = card })
end

local function buildTutorial(root: Frame)
	local card = W.card({
		Name = "Tutorial",
		Position = UDim2.fromOffset(14, 160),
		Size = UDim2.fromOffset(290, 100),
		Parent = root,
	})
	W.padding(10, 8).Parent = card
	refs.tutorialCard = card
	refs.tutorialTitle = W.text({ Size = UDim2.new(1, 0, 0, 16), Font = Theme.fontBlack, TextSize = 12, TextColor3 = C.accent, Text = "GETTING STARTED 1/5", Parent = card })
	refs.tutorialText = W.text({
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(1, 0, 1, -22),
		TextWrapped = true,
		TextSize = 14,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "",
		Parent = card,
	})
	refs.tutorialButton = W.button({
		Text = "Got it",
		Size = UDim2.fromOffset(80, 26),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, 0),
		textSize = 13,
		style = "primary",
		Visible = false,
		onClick = function()
			Store.request("TutorialAck")
		end,
		Parent = card,
	})
end

local function buildMenu(root: Frame)
	local column = W.frame({ Name = "Menu", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, -30), Size = UDim2.fromOffset(64, 6 * 60), Parent = root })
	W.list(Enum.FillDirection.Vertical, 6).Parent = column
	refs.menuDots = {}
	for i, item in MENU do
		local btn = W.button({
			Text = item.label,
			Size = UDim2.fromOffset(64, 54),
			textSize = 11,
			LayoutOrder = i,
			onClick = function()
				UI.toggle(item.id)
			end,
			Parent = column,
		})
		W.text({
			Text = item.key,
			Size = UDim2.fromOffset(16, 14),
			Position = UDim2.new(1, -3, 0, 3),
			AnchorPoint = Vector2.new(1, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
			Font = Theme.fontBold,
			TextSize = 10,
			TextColor3 = C.dim,
			Parent = btn,
		})
		local dot = W.frame({
			Size = UDim2.fromOffset(12, 12),
			Position = UDim2.new(0, 4, 0, 4),
			BackgroundColor3 = C.accent,
			BackgroundTransparency = 0,
			Visible = false,
			Parent = btn,
		})
		W.corner(UDim.new(1, 0)).Parent = dot
		W.stroke(C.black, 1.5).Parent = dot
		refs.menuDots[item.id] = dot
	end
end

local function buildArmCard(root: Frame)
	local card = W.card({
		Name = "ArmCard",
		AnchorPoint = Vector2.new(0, 1),
		-- on touch screens the left thumbstick lives bottom-left, so the card floats above it
		Position = if W.isTouch() then UDim2.new(0, 14, 1, -190) else UDim2.new(0, 14, 1, -14),
		Size = UDim2.fromOffset(250, 64),
		Parent = root,
	})
	W.padding(10, 8).Parent = card
	refs.armName = W.text({ Size = UDim2.new(1, -60, 0, 20), Font = Theme.fontBold, TextSize = 15, Text = "Starter Fists", Parent = card })
	refs.armLevel = W.text({
		Size = UDim2.fromOffset(60, 20),
		Position = UDim2.new(1, 0, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Theme.fontBold,
		TextSize = 13,
		TextColor3 = C.accent,
		Text = "Lv 0",
		Parent = card,
	})
	refs.armStats = W.text({
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = 13,
		TextColor3 = C.sub,
		Text = "",
		Parent = card,
	})
end

local function buildSkillBar(root: Frame)
	local bar = W.frame({ Name = "SkillBar", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(4 * 74, 70), Parent = root })
	W.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center).Parent = bar
	refs.skills = {}
	for i, id in SkillConfig.Order do
		local def = SkillConfig.Defs[id]
		local slot = W.new("TextButton", {
			Name = id,
			Size = UDim2.fromOffset(68, 68),
			BackgroundColor3 = C.panel,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = i,
			ClipsDescendants = true,
			Parent = bar,
		})
		W.corner(UDim.new(0, 10)).Parent = slot
		local stroke = W.stroke(def.color, 2, 0.25)
		stroke.Parent = slot
		local name = W.text({
			Size = UDim2.new(1, -4, 0, 30),
			Position = UDim2.fromOffset(2, 18),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = Theme.fontBold,
			TextSize = 10,
			Text = string.upper(def.name),
			TextColor3 = C.text,
			Parent = slot,
		})
		local key = W.text({ Position = UDim2.fromOffset(6, 3), Size = UDim2.fromOffset(20, 14), Font = Theme.fontBlack, TextSize = 12, TextColor3 = def.color, Text = tostring(def.key), Parent = slot })
		local rankText = W.text({
			Position = UDim2.new(1, -4, 1, -16),
			AnchorPoint = Vector2.new(1, 0),
			Size = UDim2.fromOffset(40, 14),
			TextXAlignment = Enum.TextXAlignment.Right,
			Font = Theme.fontBold,
			TextSize = 10,
			TextColor3 = C.sub,
			Text = "",
			Parent = slot,
		})
		local overlay = W.frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.black, BackgroundTransparency = 0.12, Visible = false, ZIndex = 3, Parent = slot })
		local timer = W.text({
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = Theme.fontBlack,
			TextSize = 20,
			Text = "",
			ZIndex = 4,
			Parent = slot,
		})
		slot.Activated:Connect(function()
			CombatController.useSkill(id)
		end)
		refs.skills[id] = { slot = slot, stroke = stroke, overlay = overlay, timer = timer, rank = rankText, name = name, key = key, def = def }
	end
end

local function buildPunchButton(root: Frame)
	if not W.isTouch() then
		return
	end
	local btn = W.new("TextButton", {
		Name = "PunchButton",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -170, 1, -30),
		Size = UDim2.fromOffset(112, 112),
		BackgroundColor3 = C.accent,
		Text = "PUNCH",
		Font = Theme.fontBlack,
		TextSize = 20,
		TextColor3 = C.black,
		AutoButtonColor = false,
		Parent = root,
	})
	W.corner(UDim.new(1, 0)).Parent = btn
	W.stroke(Color3.fromRGB(255, 226, 180), 3).Parent = btn
	btn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			CombatController.setHeld(true)
		end
	end)
	btn.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			CombatController.setHeld(false)
		end
	end)
end

-- Refresh ----------------------------------------------------------------------------------------------------------------

local function refreshStatus()
	local d = Store.data
	if not d then
		return
	end
	refs.levelText.Text = tostring(d.level)
	local need = Formulas.xpToNext(d.level)
	if d.level >= ProgressionConfig.MaxLevel then
		refs.xpBar.set(1, "MAX LEVEL")
	else
		refs.xpBar.set(d.xp / need, `{Format.compact(d.xp)} / {Format.compact(need)} XP`)
	end
	refs.coins.set(d.coins)
	refs.shards.set(d.shards)
	refs.nameText.Text = if d.rebirths > 0 then "Reforged Master" else "Forgemaster"
	refs.rebirthPill.Visible = d.rebirths > 0
	refs.rebirthPill.Text = `REBIRTH {d.rebirths}`
	local here = IslandConfig.Defs[d.islands.current]
	if here then
		local boost = Islands.boostText(here.id)
		refs.islandText.Text = if boost then `{string.upper(here.name)}  ·  {boost}` else string.upper(here.name)
		refs.islandText.TextColor3 = if boost then C.good else C.sub
	end

	local arm = Arms.Defs[d.arms.equipped]
	refs.armName.Text = arm.name
	refs.armLevel.Text = `Lv {d.arms.levels[arm.id] or 0}`
	local live = Store.live
	refs.armStats.Text = `Power {Format.compact(live.power or Store.armPower())}  ·  {string.format("%.2f", live.cooldown or arm.cooldown)}s  ·  Crit {Format.percent(live.critChance or arm.critChance)}`

	-- tutorial
	local step = ProgressionConfig.Tutorial[d.tutorial.step]
	if step then
		refs.tutorialCard.Visible = true
		refs.tutorialTitle.Text = `GETTING STARTED  {d.tutorial.step}/{#ProgressionConfig.Tutorial}`
		refs.tutorialText.Text = step.text
		refs.tutorialButton.Visible = step.id == "done"
	else
		refs.tutorialCard.Visible = false
	end

	-- menu dots
	local b = badges()
	for id, dot in refs.menuDots do
		dot.Visible = b[id] == true
	end
end

local chips: { [string]: Frame } = {}

local function refreshDynamic()
	local d = Store.data
	if not d then
		return
	end
	-- skill bar
	for id, r in refs.skills do
		local def = r.def
		local rank = d.skills.ranks[id] or 0
		local locked = d.level < def.unlockLevel
		local cd = Store.skillCooldown(id)
		local active = Store.buffRemaining(id)
		if rank < 1 then
			r.overlay.Visible = true
			r.timer.Text = if locked then `Lv {def.unlockLevel}` else "LEARN"
			r.timer.TextSize = if locked then 15 else 14
			r.timer.TextColor3 = if locked then C.dim else C.accent
			r.rank.Text = ""
		elseif cd > 0.05 then
			r.overlay.Visible = true
			r.timer.Text = string.format("%.1f", cd)
			r.timer.TextSize = 20
			r.timer.TextColor3 = C.text
			r.rank.Text = `R{rank}`
		else
			r.overlay.Visible = false
			r.timer.Text = ""
			r.rank.Text = `R{rank}`
		end
		r.stroke.Thickness = if active > 0 then 3.5 else 2
		r.stroke.Transparency = if active > 0 then 0 else 0.25
	end
	-- booster chips
	for id in d.boosters.active do
		local def = BoosterConfig.Defs[id]
		if def then
			local left = Store.boosterRemaining(id)
			local chip = chips[id]
			if not chip then
				chip = W.frame({ Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = def.color, BackgroundTransparency = 0.1, Parent = refs.boosterRow })
				W.corner(UDim.new(1, 0)).Parent = chip
				W.padding(8, 0).Parent = chip
				W.text({ Name = "T", Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Font = Theme.fontBold, TextSize = 11, TextColor3 = C.black, Text = "", Parent = chip })
				chips[id] = chip
			end
			;(chip:FindFirstChild("T") :: TextLabel).Text = `{string.upper(def.stat)} +{math.floor(def.bonus * 100)}%  {Format.clock(left)}`
		end
	end
	for id, chip in chips do
		if not d.boosters.active[id] or Store.boosterRemaining(id) <= 0 then
			chip:Destroy()
			chips[id] = nil
		end
	end
	-- target card
	local target = TargetController.current
	local isBoss = target ~= nil and target:GetAttribute("CreatureId") ~= nil and target:GetAttribute("Tier") == "boss"
	if target and target.Parent and target:GetAttribute("Alive") == true and not isBoss then -- guardians have their own bar
		local def = Rocks.Defs[target:GetAttribute("DefId") :: string]
		local hp: number = (target:GetAttribute("Hp") :: number?) or 0
		local maxHp: number = (target:GetAttribute("MaxHp") :: number?) or 1
		refs.targetCard.Visible = true
		local creatureName = target:GetAttribute("Name") :: string?
		if target:GetAttribute("CreatureId") and creatureName then
			-- a creature released from a rock: show it, its tier and what it is doing
			local tier = string.upper((target:GetAttribute("Tier") :: string?) or "normal")
			local state = (target:GetAttribute("State") :: string?) or ""
			refs.targetName.Text = creatureName
			refs.targetStage.Text = if (target:GetAttribute("Armored") :: boolean?) == true then `{tier}  ARMORED` else `{tier}  {state}`
		else
			refs.targetName.Text = def and def.name or "Rock"
			refs.targetStage.Text = (target:GetAttribute("Stage") :: string) or ""
		end
		refs.targetBar.set(hp / maxHp, `{Format.compact(hp)} / {Format.compact(maxHp)}`)
		refs.targetBar.fill.BackgroundColor3 = if def then def.colors.glow else C.accent
	else
		refs.targetCard.Visible = false
	end
end

function Hud.build(root: Frame)
	buildStatusCard(root)
	buildTargetCard(root)
	buildTutorial(root)
	buildMenu(root)
	buildArmCard(root)
	buildSkillBar(root)
	buildPunchButton(root)
	Store.changed:connect(refreshStatus)
	RunService.Heartbeat:Connect(function()
		refreshDynamic()
	end)
	if Store.data then
		refreshStatus()
	end
end

return Hud
