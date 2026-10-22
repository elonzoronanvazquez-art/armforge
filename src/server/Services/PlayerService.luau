--!strict
-- Player lifecycle: load data, create the session, spawn the character on the right island, attach the equipped arms,
-- save on leave. Characters are spawned manually (Players.CharacterAutoLoads = false) so nobody spawns before their
-- data has loaded.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local IslandConfig = require(Shared.Config.Islands)
local Sessions = require(script.Parent.Sessions)
local Sync = require(script.Parent.Sync)
local DataService = require(script.Parent.DataService)
local ArmService = require(script.Parent.ArmService)
local ProgressService = require(script.Parent.ProgressService)

local PlayerService = {}

-- islandId -> SpawnLocation (registered by the world builder)
local spawns: { [string]: SpawnLocation } = {}

function PlayerService.registerSpawn(islandId: string, spawn: SpawnLocation)
	spawns[islandId] = spawn
end

function PlayerService.spawnCFrame(islandId: string): CFrame
	local def = IslandConfig.Defs[islandId] or IslandConfig.Defs[IslandConfig.Start]
	return CFrame.new(def.arrival + Vector3.new(0, 3, 0)) * CFrame.Angles(0, math.rad(180), 0)
end

local function setupCharacter(player: Player, character: Model)
	local session = Sessions.get(player)
	if not (session and session.data) then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local hrp = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not (humanoid and hrp) then
		return
	end
	-- the character assembles over several frames: wait for every limb (and the avatar's appearance) before touching it
	for _, limb in { "UpperTorso", "LowerTorso", "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand" } do
		character:WaitForChild(limb, 10)
	end
	local waited = os.clock()
	while not player:HasAppearanceLoaded() and os.clock() - waited < 8 do
		task.wait(0.1)
	end
	humanoid.WalkSpeed = 18
	humanoid.JumpPower = 55
	humanoid.UseJumpPower = true
	-- the real avatar limbs are hidden and replaced by the equipped arm set
	ArmService.refresh(player)
	session.combat.nextAttackAt = 0
	Sync.mark(player)

	local island = session.data.islands.current
	hrp.CFrame = PlayerService.spawnCFrame(island)
	humanoid.Died:Connect(function()
		task.wait(Players.RespawnTime)
		if player.Parent and Sessions.get(player) and not session.leaving then
			player:LoadCharacterAsync()
		end
	end)
end

local function onPlayerAdded(player: Player)
	local session = Sessions.create(player)
	local data = DataService.load(player)
	if not data or not player.Parent then
		Sessions.remove(player)
		if player.Parent then
			player:Kick("ARMFORGE could not load your save data safely. Please rejoin in a moment.")
		end
		return
	end
	session.data = data
	session.loaded = true
	session.combat.armId = data.arms.equipped

	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local level = Instance.new("IntValue")
	level.Name = "Level"
	level.Value = data.level
	level.Parent = stats
	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Value = data.rebirths
	rebirths.Parent = stats
	stats.Parent = player

	player.CharacterAdded:Connect(function(character)
		task.spawn(setupCharacter, player, character)
	end)
	local spawn = spawns[data.islands.current]
	if spawn then
		player.RespawnLocation = spawn
	end
	player:LoadCharacterAsync()
	ProgressService.updateLeaderstats(player)
	Sync.now(player)
end

local function onPlayerRemoving(player: Player)
	local session = Sessions.get(player)
	if not session then
		return
	end
	if session.loaded and not session.leaving then
		session.leaving = true
		DataService.save(session, true)
	end
	Sessions.remove(player)
end

function PlayerService.start()
	Players.CharacterAutoLoads = false
	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	-- play time stat
	task.spawn(function()
		while true do
			task.wait(60)
			for _, s in Sessions.all() do
				if s.data then
					s.data.stats.playSeconds += 60
				end
			end
		end
	end)
end

return PlayerService
