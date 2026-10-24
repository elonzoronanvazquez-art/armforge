--!strict
-- Keyboard / mouse / gamepad bindings. Touch uses the on-screen PUNCH button and skill slots (see UI/Hud).
--   Mouse1 or Gamepad R2: punch (hold to keep striking)     1-4 / D-pad: skills
--   F Arms  K Skills  B Boosters  M Islands  R Rebirth  O Menu

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local CombatController = require(script.Parent.CombatController)
local Store = require(script.Parent.Parent.Store)
local UI = require(script.Parent.Parent.UI.UI)
local W = require(script.Parent.Parent.UI.Widgets)

local InputController = {}

local PANEL_KEYS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.F] = "Arms",
	[Enum.KeyCode.K] = "Skills",
	[Enum.KeyCode.B] = "Boosters",
	[Enum.KeyCode.M] = "Islands",
	[Enum.KeyCode.R] = "Rebirth",
	[Enum.KeyCode.O] = "Settings",
}

local SKILL_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.DPadLeft] = 1,
	[Enum.KeyCode.DPadUp] = 2,
	[Enum.KeyCode.DPadRight] = 3,
	[Enum.KeyCode.DPadDown] = 4,
}

local pointerHeld = false

function InputController.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

	UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if processed or UI.modalOpen() then
				return
			end
			if W.overGui(playerGui, Vector2.new(input.Position.X, input.Position.Y)) then
				return
			end
			pointerHeld = true
			CombatController.setHeld(true)
			return
		end
		if input.UserInputType == Enum.UserInputType.Gamepad1 and input.KeyCode == Enum.KeyCode.ButtonR2 then
			if not UI.modalOpen() then
				CombatController.setHeld(true)
			end
			return
		end
		if processed then
			return
		end
		local panel = PANEL_KEYS[input.KeyCode]
		if panel then
			UI.toggle(panel)
			return
		end
		-- developer mode: backtick, only for players the server authorized (it re-checks every command)
		if input.KeyCode == Enum.KeyCode.Backquote and Store.live.dev == true then
			UI.toggle("Dev")
			return
		end
		local slot = SKILL_KEYS[input.KeyCode]
		if slot then
			CombatController.useSkillSlot(slot)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and pointerHeld then
			pointerHeld = false
			CombatController.setHeld(false)
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			CombatController.setHeld(false)
		end
	end)

	-- panels (and training) pause strikes so clicking a button never swings an arm
	UI.opened:connect(function(name)
		CombatController.blocked = name ~= nil
		if name ~= nil then
			CombatController.setHeld(false)
		end
	end)
end

return InputController
