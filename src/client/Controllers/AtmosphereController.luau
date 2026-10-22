--!strict
-- Mood: blends the lighting toward the theme of the island the player is on, and spins tagged landmarks (the Halo).
-- Purely visual and local.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local IslandConfig = require(Shared.Config.Islands)

local AtmosphereController = {}

local THEMES = {
	Forgeheart = { clock = 16.2, ambient = Color3.fromRGB(70, 64, 78), outdoor = Color3.fromRGB(104, 96, 110), atmoColor = Color3.fromRGB(255, 196, 150), decay = Color3.fromRGB(150, 110, 120), density = 0.32, tint = Color3.fromRGB(255, 244, 232), brightness = 2.6 },
	Crystalfall = { clock = 11.4, ambient = Color3.fromRGB(80, 90, 130), outdoor = Color3.fromRGB(120, 138, 186), atmoColor = Color3.fromRGB(190, 210, 255), decay = Color3.fromRGB(120, 130, 190), density = 0.3, tint = Color3.fromRGB(235, 240, 255), brightness = 2.9 },
	Emberfang = { clock = 19.2, ambient = Color3.fromRGB(96, 56, 50), outdoor = Color3.fromRGB(132, 80, 70), atmoColor = Color3.fromRGB(255, 120, 80), decay = Color3.fromRGB(150, 60, 50), density = 0.42, tint = Color3.fromRGB(255, 226, 210), brightness = 2.0 },
	Voidreach = { clock = 22.5, ambient = Color3.fromRGB(60, 44, 90), outdoor = Color3.fromRGB(80, 60, 120), atmoColor = Color3.fromRGB(140, 100, 220), decay = Color3.fromRGB(60, 40, 110), density = 0.4, tint = Color3.fromRGB(230, 220, 255), brightness = 1.6 },
}

local current = ""

local function nearestIsland(pos: Vector3): string
	local best, bestDist = "Forgeheart", math.huge
	for id, def in IslandConfig.Defs do
		local d = (Vector3.new(def.center.X, 0, def.center.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude
		if d < bestDist then
			best, bestDist = id, d
		end
	end
	return best
end

local function apply(id: string)
	local theme = (THEMES :: any)[id]
	if not theme then
		return
	end
	local info = TweenInfo.new(2.5, Enum.EasingStyle.Sine)
	TweenService:Create(Lighting, info, {
		ClockTime = theme.clock,
		Ambient = theme.ambient,
		OutdoorAmbient = theme.outdoor,
		Brightness = theme.brightness,
	}):Play()
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmo then
		TweenService:Create(atmo, info, { Color = theme.atmoColor, Decay = theme.decay, Density = theme.density }):Play()
	end
	local grade = Lighting:FindFirstChild("Grade") :: ColorCorrectionEffect?
	if grade then
		TweenService:Create(grade, info, { TintColor = theme.tint }):Play()
	end
end

function AtmosphereController.start()
	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		for _, inst in CollectionService:GetTagged("Spin") do
			if inst:IsA("Model") and inst.PrimaryPart then
				local speed = (inst:GetAttribute("SpinSpeed") :: number?) or 0.05
				inst:PivotTo(inst:GetPivot() * CFrame.Angles(0, 0, speed * dt))
			end
		end
		accum += dt
		if accum >= 0.6 then
			accum = 0
			local char = Players.LocalPlayer.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp then
				local id = nearestIsland(hrp.Position)
				if id ~= current then
					current = id
					apply(id)
				end
			end
		end
	end)
end

return AtmosphereController
