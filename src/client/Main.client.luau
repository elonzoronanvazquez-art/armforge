--!strict
-- ARMFORGE client bootstrap. Order matters: remotes and store first, then presentation controllers, then input and UI.
-- A failure in one controller must never take down the others, so each start is isolated.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Shared = ReplicatedStorage:WaitForChild("Armforge")
local Net = require(Shared.Net)
local Root = script.Parent -- the "Armforge" folder this script lives in
local Controllers = Root:WaitForChild("Controllers")
local UIFolder = Root:WaitForChild("UI")

local Store = require(Root:WaitForChild("Store"))
local ArmAnimator = require(Controllers:WaitForChild("ArmAnimator"))
local CameraController = require(Controllers:WaitForChild("CameraController"))
local EffectsController = require(Controllers:WaitForChild("EffectsController"))
local TargetController = require(Controllers:WaitForChild("TargetController"))
local CombatController = require(Controllers:WaitForChild("CombatController"))
local InputController = require(Controllers:WaitForChild("InputController"))
local AtmosphereController = require(Controllers:WaitForChild("AtmosphereController"))
local DevCamController = require(Controllers:WaitForChild("DevCamController"))
local UI = require(UIFolder:WaitForChild("UI"))
local Hud = require(UIFolder:WaitForChild("Hud"))
local Notifications = require(UIFolder:WaitForChild("Notifications"))
local Panels = require(UIFolder:WaitForChild("Panels"))

local function safe(name: string, fn: () -> ())
	local ok, err = xpcall(function(): any
		return fn()
	end, debug.traceback)
	if not ok then
		warn(`[ARMFORGE] {name} failed to start: {err}`)
	end
end

print("[ARMFORGE] client boot")
Net.client()
Store.init()
Store.waitReady()

safe("ArmAnimator", ArmAnimator.start)
safe("CameraController", CameraController.start)
safe("EffectsController", EffectsController.start)
safe("TargetController", TargetController.start)
safe("CombatController", CombatController.start)
safe("AtmosphereController", AtmosphereController.start)
safe("DevCam", DevCamController.start)
safe("UI", function()
	UI.start(Panels.list(), Hud)
	Notifications.start(UI.root :: Frame)
end)
safe("InputController", InputController.start)

-- world prompts open UI panels (the prompt's "Panel" attribute names the panel)
ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
	if player ~= Players.LocalPlayer then
		return
	end
	local panel = prompt:GetAttribute("Panel")
	if type(panel) == "string" then
		UI.open(panel, { stationId = prompt:GetAttribute("StationId") })
	end
end)

print("[ARMFORGE] client ready")
