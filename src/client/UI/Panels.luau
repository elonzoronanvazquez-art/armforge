--!strict
-- Registry of modal panels, in menu order. Each module exports { name, title, size, build, refresh, onOpen?, onClose? }.

local Panels = {}

function Panels.list(): { any }
	local list = {}
	for _, name in { "ArmsPanel", "SkillsPanel", "BoostersPanel", "IslandsPanel", "RebirthPanel", "SettingsPanel", "TrainingPanel", "DevPanel" } do
		local module = script.Parent:FindFirstChild(name)
		if module then
			local ok, panel = pcall(require, module)
			if ok then
				table.insert(list, panel)
			else
				warn(`[ARMFORGE] panel {name} failed to load: {panel}`)
			end
		end
	end
	return list
end

return Panels
