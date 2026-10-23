--!strict
-- SKILLS & TRAINING: learn / rank up the four arm skills with skill points, and see the permanent training stats earned
-- at the Training Yard (with each station's requirements).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local SkillConfig = require(Shared.Config.Skills)
local Training = require(Shared.Config.Training)
local Skills = require(Shared.Logic.Skills)
local Formulas = require(Shared.Logic.Formulas)
local Format = require(Shared.Util.Format)
local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local W = require(script.Parent.Widgets)
local Messages = require(script.Parent.Messages)

local C = Theme.colors

local Panel = {}
Panel.name = "Skills"
Panel.title = "SKILLS & TRAINING"
Panel.size = Vector2.new(840, 480)

local refs: { [string]: any } = {}
local skillCards: { [string]: any } = {}
local statRows: { [string]: any } = {}

local function effectText(id: string, rank: number, armId: string): string
	local e = Skills.effect(id, math.max(1, rank), armId)
	if id == "ChargedSmash" then
		return `Damage x{string.format("%.1f", e.damageMult)}. Breaks at least {e.minChunks} chunks. Needs a rock in reach.`
	elseif id == "CriticalFocus" then
		return `+{Format.percent(e.critBonus)} crit chance for {string.format("%.1f", e.duration)}s.`
	elseif id == "Overdrive" then
		return `+{Format.percent(e.hasteBonus)} attack speed, +{Format.percent(e.powerBonus)} damage for {string.format("%.1f", e.duration)}s, then {e.overheatDuration}s of Overheat.`
	elseif id == "ShatterWave" then
		return `{Format.percent(e.damageMult)} damage to up to {e.maxTargets} rocks within {e.radius} studs.`
	end
	return ""
end

function Panel.refresh()
	local d = Store.data
	if not d then
		return
	end
	refs.points.Text = `Skill points: {d.skillPoints}`
	local armId: string = d.arms.equipped
	for _, id in SkillConfig.Order do
		local def = SkillConfig.Defs[id]
		local card = skillCards[id]
		local rank = d.skills.ranks[id] or 0
		local locked = d.level < def.unlockLevel
		card.rank.Text = if rank == 0 then "NOT LEARNED" else `RANK {rank}/{def.maxRank}`
		card.rank.TextColor3 = if rank == 0 then C.dim else def.color
		card.effect.Text = effectText(id, if rank == 0 then 1 else rank, armId)
		card.cd.Text = `Cooldown {string.format("%.1f", Skills.cooldown(d, id))}s`
		for i, pip in card.pips do
			pip.BackgroundColor3 = if i <= rank then def.color else C.panelLo
		end
		local cost = def.rankCost[rank + 1]
		local btn = card.button
		if rank >= def.maxRank then
			btn.Text = "MAX RANK"
			W.setEnabled(btn, false)
		elseif locked then
			btn.Text = `UNLOCKS AT LEVEL {def.unlockLevel}`
			W.setEnabled(btn, false)
		else
			btn.Text = `{if rank == 0 then "LEARN" else "RANK UP"}  ({cost} pt{if cost > 1 then "s" else ""})`
			W.setEnabled(btn, d.skillPoints >= cost)
		end
		card.skillKey.Text = `Key {def.key}`
	end
	for _, stat in Training.StatOrder do
		local info = Training.Stats[stat]
		local entry = d.training[stat]
		local cap = Formulas.trainingLevelCap(stat, d.level)
		local row = statRows[stat]
		row.level.Text = `Lv {entry.level}/{cap}` .. (if cap < info.maxLevel then "  (cap grows with your level)" else "")
		local need = Formulas.trainingPointsToNext(entry.level)
		if entry.level >= cap then
			row.bar.set(1, if entry.level >= info.maxLevel then "MAXED" else "Level up to train more")
		else
			row.bar.set(entry.points / need, `{entry.points} / {need}`)
		end
	end
end

function Panel.build(content: Frame)
	refs.points = W.text({ Position = UDim2.fromOffset(18, 4), Size = UDim2.fromOffset(300, 22), Font = Theme.fontBold, TextSize = 15, TextColor3 = C.accent, Text = "", Parent = content })
	local left = W.scroll({ Position = UDim2.fromOffset(14, 30), Size = UDim2.new(0, 480, 1, -40), Parent = content })
	W.list(Enum.FillDirection.Vertical, 8).Parent = left
	for i, id in SkillConfig.Order do
		local def = SkillConfig.Defs[id]
		local card = W.card({ Size = UDim2.new(1, -8, 0, 112), LayoutOrder = i, Parent = left })
		W.padding(10, 8).Parent = card
		local stroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke
		stroke.Color = def.color
		stroke.Transparency = 0.5
		W.text({ Size = UDim2.new(1, -130, 0, 20), Font = Theme.fontBlack, TextSize = 16, Text = string.upper(def.name), Parent = card })
		local rank = W.text({ Position = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(130, 20), TextXAlignment = Enum.TextXAlignment.Right, Font = Theme.fontBold, TextSize = 12, Text = "", Parent = card })
		W.text({ Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 16), TextSize = 12, TextColor3 = C.sub, Text = def.blurb, Parent = card })
		local effect = W.text({ Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 30), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextSize = 12, Text = "", Parent = card })
		local cd = W.text({ Position = UDim2.fromOffset(0, 72), Size = UDim2.fromOffset(140, 16), TextSize = 11, TextColor3 = C.dim, Text = "", Parent = card })
		local skillKey = W.text({ Position = UDim2.fromOffset(100, 72), Size = UDim2.fromOffset(60, 16), TextSize = 11, TextColor3 = def.color, Font = Theme.fontBold, Text = "", Parent = card })
		W.text({ Position = UDim2.fromOffset(0, 88), Size = UDim2.new(1, -170, 0, 14), TextSize = 10, TextColor3 = C.dim, Text = "Tradeoff: " .. def.tradeoff, Parent = card })
		local pips = {}
		local pipRow = W.frame({ Position = UDim2.new(1, -170, 0, 72), AnchorPoint = Vector2.new(0, 0), Size = UDim2.fromOffset(60, 10), Parent = card })
		W.list(Enum.FillDirection.Horizontal, 3).Parent = pipRow
		for p = 1, def.maxRank do
			local pip = W.frame({ Size = UDim2.fromOffset(10, 10), BackgroundColor3 = C.panelLo, BackgroundTransparency = 0, Parent = pipRow })
			W.corner(UDim.new(1, 0)).Parent = pip
			pips[p] = pip
		end
		local button = W.button({
			Text = "",
			Size = UDim2.fromOffset(160, 32),
			Position = UDim2.new(1, 0, 1, 0),
			AnchorPoint = Vector2.new(1, 1),
			textSize = 12,
			style = "primary",
			onClick = function()
				Messages.report(Store.request("LearnSkill", { skillId = id }), nil, "Upgrade")
			end,
			Parent = card,
		})
		skillCards[id] = { rank = rank, effect = effect, cd = cd, pips = pips, button = button, skillKey = skillKey }
	end

	-- training stats
	local right = W.card({ Position = UDim2.new(0, 506, 0, 8), Size = UDim2.new(1, -520, 1, -22), Parent = content })
	W.padding(12, 10).Parent = right
	W.text({ Size = UDim2.new(1, 0, 0, 18), Font = Theme.fontBlack, TextSize = 15, TextColor3 = C.accent, Text = "TRAINING STATS", Parent = right })
	W.text({ Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 30), TextWrapped = true, TextSize = 11, TextColor3 = C.sub, TextYAlignment = Enum.TextYAlignment.Top, Text = "Earned at the Training Yard. Permanent, but reset by Rebirth.", Parent = right })
	local list = W.frame({ Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 1, -54), Parent = right })
	W.list(Enum.FillDirection.Vertical, 8).Parent = list
	for i, stat in Training.StatOrder do
		local info = Training.Stats[stat]
		local station: Training.Station? = nil
		for _, id in Training.Order do
			if Training.Stations[id].stat == stat then
				station = Training.Stations[id]
			end
		end
		local row = W.frame({ Size = UDim2.new(1, 0, 0, 74), LayoutOrder = i, Parent = list })
		W.text({ Size = UDim2.new(0.5, 0, 0, 18), Font = Theme.fontBold, TextSize = 14, Text = info.name, Parent = row })
		local level = W.text({ Position = UDim2.fromScale(1, 0), AnchorPoint = Vector2.new(1, 0), Size = UDim2.new(0.8, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 11, TextColor3 = C.sub, Text = "", Parent = row })
		local bar = W.bar({ Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 14), color = if station then station.color else C.accent, textSize = 10, Parent = row })
		W.text({ Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 14), TextSize = 11, TextColor3 = C.dim, Text = info.text, Parent = row })
		if station then
			W.text({ Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 0, 14), TextSize = 11, TextColor3 = C.dim, Text = `{station.name}  ·  unlocks at level {station.unlockLevel}`, Parent = row })
		end
		statRows[stat] = { level = level, bar = bar }
	end
end

return Panel
