--!strict
-- The aerial tramway schedule: two cabins on one cable swap ends. Pure function of a clock, so the server, the tests and the dev tools
-- agree on where each cabin is and which one is docked where. Position 0 = base station, 1 = summit station.

local Mountain = require(script.Parent.Parent.Config.Mountain)

local Tram = {}

export type State = {
	docked: boolean,
	leg: number, -- 1: cabin 1 goes up this cycle, 2: cabin 2 goes up
	cabin1: number, -- 0..1 along the cable
	cabin2: number,
	departsIn: number, -- seconds until the next departure (0 while moving)
	arrivesIn: number, -- seconds until the cabins dock (0 while docked)
	baseCabin: number?, -- which cabin (1 / 2) is docked at the base station, nil while moving
	summitCabin: number?,
}

local function ease(f: number): number
	f = math.clamp(f, 0, 1)
	return f * f * (3 - 2 * f)
end

function Tram.cycle(): number
	local cfg = Mountain.Tram
	return 2 * (cfg.dock + cfg.travel)
end

function Tram.state(t: number): State
	local cfg = Mountain.Tram
	local half = cfg.dock + cfg.travel
	local x = t % (2 * half)
	local leg = if x < half then 1 else 2
	local local_ = x - (leg - 1) * half
	-- in leg 1 cabin 1 starts at the base; in leg 2 it starts at the summit and comes down
	if local_ < cfg.dock then
		local c1 = if leg == 1 then 0 else 1
		return {
			docked = true,
			leg = leg,
			cabin1 = c1,
			cabin2 = 1 - c1,
			departsIn = cfg.dock - local_,
			arrivesIn = 0,
			baseCabin = if leg == 1 then 1 else 2,
			summitCabin = if leg == 1 then 2 else 1,
		}
	end
	local f = ease((local_ - cfg.dock) / cfg.travel)
	local c1 = if leg == 1 then f else 1 - f
	return { docked = false, leg = leg, cabin1 = c1, cabin2 = 1 - c1, departsIn = 0, arrivesIn = cfg.travel - (local_ - cfg.dock), baseCabin = nil, summitCabin = nil }
end

function Tram.position(state: State, cabin: number): number
	return if cabin == 1 then state.cabin1 else state.cabin2
end

-- May a rider at `station` ("base" | "summit") board right now? Returns the cabin and nil, or nil and why not.
function Tram.canBoard(state: State, station: string, riders: number): (number?, string?)
	local cfg = Mountain.Tram
	if not state.docked then
		return nil, "The tram is between stations."
	end
	if state.departsIn < cfg.boardCutoff then
		return nil, "The tram is about to leave."
	end
	local cabin = if station == "base" then state.baseCabin else state.summitCabin
	if not cabin then
		return nil, "No cabin is docked here."
	end
	if riders >= cfg.capacity then
		return nil, "The cabin is full."
	end
	return cabin, nil
end

return Tram
