--!strict
-- STUDIO-ONLY: lets the development tooling hold the camera at a chosen pose (workspace attributes AF_DevCam /
-- AF_DevFov) so playtest screenshots can be framed. Inert in live servers.

local RunService = game:GetService("RunService")

local DevCamController = {}

function DevCamController.start()
	if not RunService:IsStudio() then
		return
	end
	RunService:BindToRenderStep("ArmforgeDevCam", Enum.RenderPriority.Camera.Value + 2, function()
		local pose = workspace:GetAttribute("AF_DevCam")
		local cam = workspace.CurrentCamera
		if cam and typeof(pose) == "CFrame" then
			cam.CameraType = Enum.CameraType.Scriptable
			cam.CFrame = pose
			cam.FieldOfView = (workspace:GetAttribute("AF_DevFov") :: number?) or 70
		end
	end)
end

return DevCamController
