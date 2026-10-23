--!strict
-- ARMFORGE server bootstrap. The Rojo place is empty: the world, rocks and every system are created here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Armforge")

local Net = require(Shared.Net)
local Services = script.Parent.Services

local DataService = require(Services.DataService)
local Sync = require(Services.Sync)
local PlayerService = require(Services.PlayerService)
local ProgressService = require(Services.ProgressService)
local RockService = require(Services.RockService)
local EncounterService = require(Services.EncounterService)
local CombatService = require(Services.CombatService)
local TrainingService = require(Services.TrainingService)
local ProgressionServices = require(Services.ProgressionServices)
local Requests = require(Services.Requests)
local WorldBuilder = require(script.Parent.World.WorldBuilder)
local DevTools = require(script.Parent.Dev.DevTools)

local t0 = os.clock()
print("[ARMFORGE] server boot")

Net.server()
DataService.init()

local world = WorldBuilder.build(PlayerService.registerSpawn)
RockService.init(world)
EncounterService.init(world)
EncounterService.start()
require(script.Parent.World.RockBuilder).preload()
local rockCount = RockService.populate()
print(`[ARMFORGE] world built in {string.format("%.1f", os.clock() - t0)}s, {rockCount} rocks`)

ProgressService.init()
RockService.setRewardHandler(ProgressService.rockReward)
Sync.start()
CombatService.start()
TrainingService.start()
ProgressionServices.start()
Requests.start()
DataService.start()
DevTools.init()
PlayerService.start()

workspace:SetAttribute("ArmforgeReady", true)
print("[ARMFORGE] ready")
