--!strict
-- Small deterministic PRNG (Park-Miller / MINSTD). Used wherever the same seed must give the same result on the
-- server, the client and in the Lune tests (rock layouts, chip variants, loot rolls in simulations).

export type Rng = {
	state: number,
	next: (self: Rng) -> number,
	range: (self: Rng, lo: number, hi: number) -> number,
	int: (self: Rng, lo: number, hi: number) -> number,
	chance: (self: Rng, p: number) -> boolean,
	pick: <T>(self: Rng, list: { T }) -> T,
	unit: (self: Rng) -> (number, number, number),
}

local MOD = 2147483647
local MULT = 48271

local Rng = {}
Rng.__index = Rng

function Rng.new(seed: number): Rng
	local s = math.floor(math.abs(seed)) % MOD
	if s == 0 then
		s = 1
	end
	local self = setmetatable({ state = s }, Rng)
	-- warm up so neighbouring seeds diverge
	for _ = 1, 3 do
		(self :: any):next()
	end
	return self :: any
end

function Rng.next(self: Rng): number
	self.state = (self.state * MULT) % MOD
	return (self.state - 1) / (MOD - 1)
end

function Rng.range(self: Rng, lo: number, hi: number): number
	return lo + (hi - lo) * self:next()
end

function Rng.int(self: Rng, lo: number, hi: number): number
	return lo + math.floor(self:next() * (hi - lo + 1))
end

function Rng.chance(self: Rng, p: number): boolean
	return self:next() < p
end

function Rng.pick<T>(self: Rng, list: { T }): T
	return list[self:int(1, #list)]
end

-- Uniform point on the unit sphere.
function Rng.unit(self: Rng): (number, number, number)
	local z = self:range(-1, 1)
	local a = self:range(0, math.pi * 2)
	local r = math.sqrt(math.max(0, 1 - z * z))
	return r * math.cos(a), z, r * math.sin(a)
end

return Rng
