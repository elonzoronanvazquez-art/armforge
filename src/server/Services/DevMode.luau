--!strict
-- Developer mode: server-authoritative test commands for authorized players (Services/DevAccess). It exists so the whole game can be tested
-- without grinding: coins, XP, levels, rebirths, every island, every arm, skills, boosters, teleports, god mode, more damage, more speed,
-- Summit Momentum and a profile reset. Data commands live in Logic/DevCommands (pure, tested); the ones that need the live world are here.
--
-- Every call re-checks authorization, so a hacked client cannot use it, and nothing here runs unless a request names it. In a live (non-Studio)
-- server only the UserIds in Config/Game.Dev.allowedUserIds and the place's owner get access; see docs/DEV_MODE.md.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Armforge")
local IslandConfig = require(Shared.Config.Islands)
local Mountain = require(Shared.Config.Mountain)
local Arms = require(Shared.Config.Arms)
local DataSchema = require(Shared.Logic.DataSchema)
local DevCommands = require(Shared.Logic.DevCommands)
local Combat = require(Shared.Logic.Combat)
local Momentum = require(Shared.Logic.Momentum)
local Validate = require(Shared.Util.Validate)
local Sessions = require(script.Parent.Sessions)
local Sync = require(script.Parent.Sync)
local DevAccess = require(script.Parent.DevAccess)
local ZoneService = require(script.Parent.ZoneService)
local ZoneConfig = require(Shared.Config.Zones)
local ProgressService = require(script.Parent.ProgressService)
local ArmService = require(script.Parent.ArmService)
local PlayerService = require(script.Parent.PlayerService)
local RockService = require(script.Parent.RockService)

local DevMode = {}

type Result = DevCommands.Result

local function fail(msg: string): Result
	return { ok = false, msg = msg }
end

local function done(msg: string): Result
	return { ok = true, msg = msg }
end

local function humanoidOf(player: Player): (Humanoid?, BasePart?)
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid"), char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function applySpeed(player: Player, session: Sessions.Session)
	local hum = humanoidOf(player)
	local speed = session.flags.devSpeed
	if hum and type(speed) == "number" then
		hum.WalkSpeed = speed
	end
end

-- Moves the player to an island the way Travel does, without the Skyport or the unlock rules.
local function goTo(player: Player, session: Sessions.Session, islandId: string): Result
	local def = IslandConfig.Defs[islandId]
	if not def then
		return fail(`unknown island "{islandId}"; try one of: {table.concat(IslandConfig.Order, ", ")}`)
	end
	if def.comingSoon then
		return fail(`{def.name} is not playable yet`)
	end
	local _, hrp = humanoidOf(player)
	if not hrp then
		return fail("no character")
	end
	session.data.islands.unlocked[islandId] = true
	session.data.islands.current = islandId
	hrp.CFrame = PlayerService.spawnCFrame(islandId)
	ProgressService.notify(player, "Island", { id = islandId, name = def.name, tagline = def.tagline })
	return done(`teleported to {def.name}`)
end

local function gotoSeal(player: Player, session: Sessions.Session, islandId: string): Result
	local _, hrp = humanoidOf(player)
	if not hrp then
		return fail("no character")
	end
	for _, entry in RockService.all() do
		if entry.island == islandId and entry.def.size == "seal" then
			session.data.islands.unlocked[islandId] = true
			session.data.islands.current = islandId
			hrp.CFrame = CFrame.new(entry.center + Vector3.new(0, 3, entry.state.layout.radius + 6))
			return done(`at a seal on {islandId} ({entry.def.name})`)
		end
	end
	return fail(`no seal found on {islandId}`)
end

local function resetProfile(player: Player, session: Sessions.Session): Result
	local fresh = DataSchema.default()
	local data = session.data
	for k in data do
		data[k] = nil
	end
	for k, v in fresh do
		data[k] = v
	end
	data.firstJoin = os.time()
	session.combat = Combat.newState("Starter")
	session.training = nil
	session.momentum = nil
	session.zone = nil
	session.flags.devGod = nil
	session.flags.devPower = nil
	session.flags.devSpeed = nil
	local hum, hrp = humanoidOf(player)
	if hum then
		hum.WalkSpeed = 16
	end
	if hrp then
		hrp.CFrame = PlayerService.spawnCFrame(IslandConfig.Start)
	end
	ArmService.refresh(player)
	return done("profile reset to a brand new player")
end

-- Commands that need the live world. Each takes (player, session, args).
local SERVER_COMMANDS: { [string]: (Player, Sessions.Session, { string }) -> Result } = {
	god = function(player, session, args)
		local want = args[1]
		local on = if want == "on" then true elseif want == "off" then false else not session.flags.devGod
		session.flags.devGod = if on then true else nil
		local hum = humanoidOf(player)
		if on and hum then
			hum.Health = hum.MaxHealth
		end
		return done(`god mode {if on then "ON: creatures cannot hurt you" else "OFF"}`)
	end,
	power = function(player, session, args)
		local n = Validate.number(tonumber(args[1] or ""), 1, 1e7)
		if not n then
			return fail("usage: power <1-10000000>  (multiplies the damage you deal to rocks and creatures; 1 = normal)")
		end
		session.flags.devPower = if n > 1 then n else nil
		return done(`damage x{n}`)
	end,
	speed = function(player, session, args)
		local n = Validate.number(tonumber(args[1] or ""), 0, 250)
		if not n then
			return fail("usage: speed <8-250>  (0 = normal)")
		end
		session.flags.devSpeed = if n >= 8 then n else nil
		local hum = humanoidOf(player)
		if hum then
			hum.WalkSpeed = if n >= 8 then n else 16
		end
		return done(`walk speed {if n >= 8 then tostring(n) else "normal"}`)
	end,
	equip = function(player, session, args)
		local want = string.lower(args[1] or "")
		for id in Arms.Defs do
			if string.lower(id) == want then
				if not session.data.arms.owned[id] then
					return fail(`you do not own {id}; run unlockarms first`)
				end
				local r = ArmService.equip(player, id)
				return if r.ok then done(`equipped {id}`) else fail(`could not equip {id}: {tostring(r.err)}`)
			end
		end
		return fail(`usage: equip <arm>  ({table.concat(Arms.Order, ", ")})`)
	end,
	heal = function(player)
		local hum = humanoidOf(player)
		if not hum then
			return fail("no character")
		end
		hum.Health = hum.MaxHealth
		return done("healed")
	end,
	-- every skill and signature cooldown, instantly (testing the moves back to back)
	resetcd = function(player, session)
		table.clear(session.combat.skillReady)
		Sync.mark(player)
		return done("all skill and signature cooldowns cleared")
	end,
	goto = function(player, session, args)
		local id = Validate.id(args[1])
		if not id then
			return fail("usage: goto <island>")
		end
		-- zones (The Atlantic Sea, the Canopy Grove) first, then the ladder; any capitalisation
		for zoneId, zone in ZoneConfig.Defs do
			if string.lower(zoneId) == string.lower(id) then
				local ok, why = ZoneService.enter(player, zoneId)
				return if ok then done(`teleported to {zone.name}`) else fail(`could not enter {zone.name}: {tostring(why)}`)
			end
		end
		for islandId in IslandConfig.Defs do
			if string.lower(islandId) == string.lower(id) then
				return goTo(player, session, islandId)
			end
		end
		return goTo(player, session, id)
	end,
	home = function(player, session)
		local ok, why = ZoneService.leave(player)
		return if ok then done("back on the ladder") else fail(`could not leave: {tostring(why)}`)
	end,
	seal = function(player, session, args)
		local island = Validate.id(args[1]) or session.data.islands.current
		for islandId in IslandConfig.Defs do
			if string.lower(islandId) == string.lower(island) then
				return gotoSeal(player, session, islandId)
			end
		end
		return fail(`unknown island "{island}"`)
	end,
	momentum = function(player, session)
		if Momentum.grant(session, Mountain.Island, os.clock()) then
			return done(`Summit Momentum granted ({Momentum.text(Mountain.Island) or ""})`)
		end
		return fail("that island has no momentum")
	end,
	reset = function(player, session, args)
		if args[1] ~= "confirm" then
			return fail("this wipes your progress. Type: reset confirm")
		end
		return resetProfile(player, session)
	end,
}

SERVER_COMMANDS.help = function()
	local names: { string } = {}
	for _, n in DevCommands.Names do
		table.insert(names, n)
	end
	for n in SERVER_COMMANDS do
		table.insert(names, n)
	end
	table.sort(names)
	return done("commands: " .. table.concat(names, ", "))
end

function DevMode.allowed(player: Player): boolean
	return DevAccess.allowed(player)
end

-- Runs one command line for a player. Returns {ok, msg}. The line is untrusted.
function DevMode.run(player: Player, line: any): Result
	if not DevAccess.allowed(player) then
		return fail("developer mode is not enabled for you")
	end
	local text = Validate.string(line, 96)
	if not text or text == "" then
		return fail("empty command; type help")
	end
	local session = Sessions.ready(player)
	if not session then
		return fail("your data is not loaded yet")
	end
	local name, args = DevCommands.parse(text)
	local server = SERVER_COMMANDS[name]
	local result: Result
	if server then
		result = server(player, session, args)
	elseif DevCommands.has(name) then
		result = DevCommands.apply(session.data, name, args)
		if result.ok then
			ProgressService.updateLeaderstats(player)
			if name == "kit" then
				-- a ready-to-test loadout: wear the strongest arm
				ArmService.equip(player, Arms.Order[#Arms.Order])
			end
		end
	else
		return fail(`unknown command "{name}"; type help`)
	end
	if result.ok then
		print(`[ARMFORGE] dev: {player.Name} ran "{text}"`)
		Sync.now(player)
	end
	return result
end

function DevMode.start()
	DevAccess.start()
	-- keep the dev walk speed across respawns
	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			local session = Sessions.get(player)
			if session and session.flags.devSpeed then
				task.wait(0.5)
				applySpeed(player, session)
			end
		end)
	end
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerAdded:Connect(watch)
end

return DevMode
