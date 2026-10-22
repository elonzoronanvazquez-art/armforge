--!strict
-- Camera feedback: proportional shake and a quick FOV kick on heavy hits. Runs after Roblox's own camera each frame.

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local Game = require(Shared.Config.Game)
local Store = require(script.Parent.Parent.Store)

local CameraController = {}

local shakeAmp = 0
local shakeTime = 0
local shakeDuration = 0.001
local fovKick = 0
local seed = math.random() * 100
local baseFov = 70
local lastFov: number? = nil

-- amount 0..1 (1 = the biggest hits). duration in seconds.
function CameraController.shake(amount: number, duration: number?)
	local settings = Store.data and Store.data.settings
	local scale = if settings then settings.shake else 1
	if settings and settings.reduceFx then
		scale *= 0.4
	end
	local amp = math.clamp(amount, 0, Game.Budgets.shakeMax) * scale
	if amp <= 0.005 then
		return
	end
	if amp > shakeAmp * (1 - shakeTime / shakeDuration) then
		shakeAmp = amp
		shakeTime = 0
		shakeDuration = duration or (0.12 + amount * 0.22)
	end
	fovKick = math.max(fovKick, amp * 3.2)
end

function CameraController.start()
	RunService:BindToRenderStep("ArmforgeCameraFx", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		if shakeAmp > 0 then
			shakeTime += dt
			local k = 1 - math.clamp(shakeTime / shakeDuration, 0, 1)
			if k <= 0 then
				shakeAmp = 0
			else
				local t = os.clock() * 55 + seed
				local a = shakeAmp * k * k
				local ox = (math.noise(t, 0.3, 0) * a) * 0.5
				local oy = (math.noise(0.7, t, 0) * a) * 0.5
				local rz = math.noise(0, 0.9, t) * a * 0.012
				cam.CFrame = cam.CFrame * CFrame.new(ox, oy, 0) * CFrame.Angles(0, 0, rz)
			end
		end
		-- FOV kick relative to whatever FOV the game / user has set (tracked so it never accumulates)
		if lastFov == nil or math.abs(cam.FieldOfView - lastFov) > 0.001 then
			baseFov = cam.FieldOfView
		end
		if fovKick > 0.01 then
			fovKick = fovKick * math.exp(-dt * 14)
			lastFov = baseFov - fovKick
			cam.FieldOfView = lastFov
		elseif lastFov ~= nil then
			fovKick = 0
			cam.FieldOfView = baseFov
			lastFov = nil
		end
	end)
end

return CameraController
