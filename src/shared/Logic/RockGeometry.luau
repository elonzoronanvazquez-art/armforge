--!strict
-- Deterministic chunk layout for a rock. A rock is three layers of chunks:
--   layer 1  SHELL  the outer surface; removable any time (stripped around the point of impact)
--   layer 2  MID    the exposed mineral layer; removable once the shell chunk covering it is gone
--   layer 3  CORE   reserved; only goes in the final collapse
-- The same (def, seed) always yields the same layout on the server and in tests. Positions are local to the rock's
-- ground contact point (x/z centred, y up).

local Config = script.Parent.Parent.Config
local RockConfig = require(Config.Rocks)
local Rng = require(script.Parent.Parent.Util.Rng)

local RockGeometry = {}

export type Chunk = {
	index: number,
	layer: number,
	cell: number,
	cover: number?, -- index of the shell chunk hiding this mid chunk (nil = already exposed)
	dir: Vector3,
	pos: Vector3,
	size: Vector3, -- X/Y tangent extents, Z thickness along `dir`
	roll: number,
	shape: string, -- Block | Wedge | Ball | Shard
	variant: number,
}

export type Layout = {
	chunks: { Chunk },
	center: Vector3,
	radius: number,
	height: number,
	removable: number, -- shell + mid chunks (the ones hits can strip)
	shellCount: number,
	midCount: number,
	coreCount: number,
}

local GOLDEN = 2.399963229728653

local function ring(n: number, yHi: number, yLo: number, offset: number): { Vector3 }
	local out = {}
	for i = 0, n - 1 do
		local y = yHi - (yHi - yLo) * (i + 0.5) / n
		local r = math.sqrt(math.max(0, 1 - y * y))
		local th = i * GOLDEN + offset
		table.insert(out, Vector3.new(r * math.cos(th), y, r * math.sin(th)))
	end
	return out
end

local function hashId(id: string): number
	local h = 7
	for i = 1, #id do
		h = (h * 31 + string.byte(id, i)) % 2147483629
	end
	return h
end

local KIND = {
	Boulder = { ax = 1.0, ay = 0.55, az = 1.0, yHi = 1.0, yLo = -0.15, taper = 0.0, shapes = { "Block", "Block", "Wedge", "Ball" } },
	Slab = { ax = 0.85, ay = 0.5, az = 1.1, yHi = 0.92, yLo = -0.1, taper = 0.15, shapes = { "Block", "Block", "Wedge" } },
	Spire = { ax = 1.0, ay = 0.5, az = 1.0, yHi = 1.0, yLo = -0.45, taper = 0.5, shapes = { "Wedge", "Wedge", "Block" } },
	Geode = { ax = 1.0, ay = 0.5, az = 1.0, yHi = 0.42, yLo = -0.25, taper = 0.0, shapes = { "Block", "Wedge", "Block" } },
}

function RockGeometry.generate(def: RockConfig.RockDef, seed: number): Layout
	local rng = Rng.new(seed * 7919 + hashId(def.id))
	local kind = (KIND :: any)[def.shape.kind] or KIND.Boulder
	local R, H = def.shape.radius, def.shape.height
	local ax, ay, az = R * kind.ax, H * kind.ay, R * kind.az
	local cy = H * 0.46
	local center = Vector3.new(0, cy, 0)

	local total = def.shape.chunks
	local coreN = def.shape.core
	local nonCore = total - coreN
	local nShell = math.max(3, math.floor(nonCore * RockConfig.LayerSplit.shell + 0.5))
	local nMid = nonCore - nShell

	local chunks: { Chunk } = {}
	local offset = rng:range(0, math.pi * 2)

	local function taper(y: number): number
		return 1 - kind.taper * math.max(0, y)
	end

	local function place(dir: Vector3, f: number): Vector3
		local t = taper(dir.Y)
		return center + Vector3.new(dir.X * ax * f * t, dir.Y * ay * f, dir.Z * az * f * t)
	end

	-- approximate covered surface -> cell size
	local effR = (ax + ay + az) / 3
	local coverage = (kind.yHi - kind.yLo) / 2
	local area = 4 * math.pi * (effR * 0.9) ^ 2 * coverage
	local cell = math.sqrt(area / nShell) * 1.32
	local shellT = R * 0.52

	-- shell
	local shellDirs = ring(nShell, kind.yHi, kind.yLo, offset)
	local shellIndex: { number } = {}
	for i, dir in shellDirs do
		local pos = place(dir, 0.76)
		local chunk: Chunk = {
			index = #chunks + 1,
			layer = 1,
			cell = i,
			cover = nil,
			dir = dir,
			pos = pos,
			size = Vector3.new(cell * rng:range(0.85, 1.25), cell * rng:range(0.85, 1.25), shellT * rng:range(0.85, 1.2)),
			roll = rng:range(0, math.pi * 2),
			shape = rng:pick(kind.shapes),
			variant = rng:int(1, 3),
		}
		table.insert(chunks, chunk)
		table.insert(shellIndex, chunk.index)
	end

	-- mid layer
	local isGeode = def.shape.kind == "Geode"
	local crown = if isGeode then math.ceil(nMid * 0.55) else 0
	local sideMid = nMid - crown
	for i = 1, sideMid do
		local coverCell = math.clamp(math.floor((i - 0.5) * nShell / math.max(1, sideMid)) + 1, 1, nShell)
		local dir = shellDirs[coverCell]
		local pos = place(dir, 0.46)
		table.insert(chunks, {
			index = #chunks + 1,
			layer = 2,
			cell = coverCell,
			cover = shellIndex[coverCell],
			dir = dir,
			pos = pos,
			size = Vector3.new(cell * rng:range(0.8, 1.1), cell * rng:range(0.8, 1.1), shellT * rng:range(0.8, 1.1)),
			roll = rng:range(0, math.pi * 2),
			shape = if isGeode then "Shard" else rng:pick(kind.shapes),
			variant = rng:int(1, 3),
		})
	end
	-- geode crown: exposed crystals sprouting from the open top
	if crown > 0 then
		local crownDirs = ring(crown, 1, 0.52, offset + 1)
		for i, dir in crownDirs do
			local pos = place(dir, 0.62)
			table.insert(chunks, {
				index = #chunks + 1,
				layer = 2,
				cell = nShell + i,
				cover = nil,
				dir = dir,
				pos = pos,
				size = Vector3.new(cell * 0.55, cell * 0.55, ay * rng:range(0.55, 0.9)),
				roll = rng:range(0, math.pi * 2),
				shape = "Shard",
				variant = rng:int(1, 3),
			})
		end
	end

	-- core
	for i = 1, coreN do
		local ux, uy, uz = rng:unit()
		local dir = Vector3.new(ux, math.abs(uy), uz)
		local pos = center + Vector3.new(ux * R * 0.16, uy * ay * 0.12, uz * R * 0.16)
		local s = R * rng:range(0.42, 0.6)
		table.insert(chunks, {
			index = #chunks + 1,
			layer = 3,
			cell = 0,
			cover = nil,
			dir = dir,
			pos = pos,
			size = Vector3.new(s, s, s),
			roll = rng:range(0, math.pi * 2),
			shape = if i % 2 == 0 then "Ball" else "Shard",
			variant = rng:int(1, 3),
		})
		if i == 1 then
			-- keep the first core chunk dead centre
			chunks[#chunks].pos = center
		end
	end

	return {
		chunks = chunks,
		center = center,
		radius = R,
		height = H,
		removable = nShell + nMid,
		shellCount = nShell,
		midCount = nMid,
		coreCount = coreN,
	}
end

return RockGeometry
