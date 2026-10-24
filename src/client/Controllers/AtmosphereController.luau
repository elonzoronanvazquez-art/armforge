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
local Assets = require(Shared.Config.Assets)
local Store = require(script.Parent.Parent.Store)

local AtmosphereController = {}

local THEMES = {
	Forgeheart = { clock = 16.2, ambient = Color3.fromRGB(70, 64, 78), outdoor = Color3.fromRGB(104, 96, 110), atmoColor = Color3.fromRGB(255, 196, 150), decay = Color3.fromRGB(150, 110, 120), density = 0.32, tint = Color3.fromRGB(255, 244, 232), brightness = 2.6 },
	Crystalfall = { clock = 14.8, ambient = Color3.fromRGB(70, 84, 124), outdoor = Color3.fromRGB(104, 122, 170), atmoColor = Color3.fromRGB(170, 196, 255), decay = Color3.fromRGB(110, 120, 190), density = 0.34, tint = Color3.fromRGB(230, 236, 255), brightness = 2.0 },
	Emberfang = { clock = 17.6, ambient = Color3.fromRGB(128, 82, 74), outdoor = Color3.fromRGB(176, 112, 96), atmoColor = Color3.fromRGB(255, 130, 90), decay = Color3.fromRGB(160, 70, 56), density = 0.4, tint = Color3.fromRGB(255, 230, 214), brightness = 2.8 },
	Mossveil = { clock = 11.4, ambient = Color3.fromRGB(70, 104, 80), outdoor = Color3.fromRGB(108, 142, 100), atmoColor = Color3.fromRGB(176, 226, 170), decay = Color3.fromRGB(84, 134, 92), density = 0.38, tint = Color3.fromRGB(236, 255, 236), brightness = 2.3 },
	Dustwake = { clock = 13.4, ambient = Color3.fromRGB(150, 122, 92), outdoor = Color3.fromRGB(190, 158, 118), atmoColor = Color3.fromRGB(240, 204, 150), decay = Color3.fromRGB(214, 160, 100), density = 0.3, tint = Color3.fromRGB(255, 240, 214), brightness = 3.0 },
	Cogspire = { clock = 15.6, ambient = Color3.fromRGB(116, 96, 76), outdoor = Color3.fromRGB(160, 132, 100), atmoColor = Color3.fromRGB(214, 176, 124), decay = Color3.fromRGB(150, 110, 70), density = 0.42, tint = Color3.fromRGB(255, 236, 210), brightness = 2.4 },
	Voidreach = { clock = 22.5, ambient = Color3.fromRGB(60, 44, 90), outdoor = Color3.fromRGB(80, 60, 120), atmoColor = Color3.fromRGB(140, 100, 220), decay = Color3.fromRGB(60, 40, 110), density = 0.4, tint = Color3.fromRGB(230, 220, 255), brightness = 1.6 },
}

local current = ""
local beds: { [string]: Sound } = {}

-- One looping sound per island; only the current island's bed is audible (cross-faded).
local function setupBeds()
	for id, def in Assets.Ambience do
		local s = Instance.new("Sound")
		s.Name = "Ambience_" .. id
		s.SoundId = def.id
		s.Looped = true
		s.Volume = 0
		s.RollOffMode = Enum.RollOffMode.Inverse
		s.Parent = game:GetService("SoundService")
		s:Play()
		beds[id] = s
	end
end

local function fadeBeds(islandId: string)
	local sfx = if Store.data then Store.data.settings.sfx else 1
	for id, s in beds do
		local target = if id == islandId then Assets.Ambience[id].volume * sfx else 0
		TweenService:Create(s, TweenInfo.new(2.5), { Volume = target }):Play()
	end
end

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
	fadeBeds(id)
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
	setupBeds()
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
