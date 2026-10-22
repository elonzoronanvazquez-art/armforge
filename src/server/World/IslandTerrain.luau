--!strict
-- Sculpts an island with Terrain:WriteVoxels from a procedural height field (noise + hand-placed features), with
-- surface materials chosen by slope, height and patch noise. Smooth top surfaces come from fractional occupancy.

local Terrain = workspace.Terrain

local IslandTerrain = {}

export type Feature = {
	kind: string, -- hill | flat | pit | ridge
	pos: Vector3,
	radius: number,
	height: number?, -- hill: peak height; pit: depth
	target: number?, -- flat: height to flatten toward
	material: Enum.Material?, -- surface material override inside the feature
	angle: number?, -- ridge direction (radians)
	length: number?, -- ridge half length
}

export type Spec = {
	center: Vector3,
	radius: number,
	plateau: number, -- 0..1 fraction of the radius that stays flat
	plateauH: number,
	seaLevel: number,
	floor: number,
	noiseScale: number,
	noiseAmp: number,
	coastWobble: number,
	seed: number,
	features: { Feature },
	ground: Enum.Material,
	ground2: Enum.Material,
	rock: Enum.Material,
	shore: Enum.Material,
	deep: Enum.Material,
}

local VOX = 4
local Y_MIN = -28 -- studs; multiple of VOX
local Y_LAYERS = 18 -- covers -28 .. 44
local TILE = 20

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function heightAt(spec: Spec, x: number, z: number): number
	local dx, dz = x - spec.center.X, z - spec.center.Z
	local r = math.sqrt(dx * dx + dz * dz)
	local angle = math.atan2(dz, dx)
	local wobble = 1 + spec.coastWobble * math.noise(math.cos(angle) * 1.7 + spec.seed, math.sin(angle) * 1.7, spec.seed * 0.37)
	local t = r / (spec.radius * wobble)
	local base: number
	if t <= spec.plateau then
		base = spec.plateauH
	else
		local f = smooth((t - spec.plateau) / (1 - spec.plateau))
		base = spec.plateauH + (spec.floor - spec.plateauH) * f
	end
	-- noise lifts the plateau into rolling ground, fading toward the coast
	local nWeight = 1 - smooth((t - spec.plateau * 0.8) / (1.1 - spec.plateau * 0.8))
	local n = math.noise(x / spec.noiseScale + spec.seed, z / spec.noiseScale, spec.seed * 0.11) * 0.7
		+ math.noise(x / (spec.noiseScale * 0.38), z / (spec.noiseScale * 0.38) + 9.3, spec.seed) * 0.3
	local h = base + n * spec.noiseAmp * nWeight
	for _, f in spec.features do
		local d = math.sqrt((x - f.pos.X) ^ 2 + (z - f.pos.Z) ^ 2)
		if f.kind == "hill" then
			local k = smooth(1 - d / f.radius)
			h += (f.height or 8) * k * k
		elseif f.kind == "pit" then
			local k = smooth(1 - d / f.radius)
			h -= (f.height or 6) * k
		elseif f.kind == "flat" then
			local k = smooth((f.radius - d) / math.max(6, f.radius * 0.25))
			h = h + ((f.target or spec.plateauH) - h) * k
		elseif f.kind == "ridge" then
			local a = f.angle or 0
			local ca, sa = math.cos(a), math.sin(a)
			local lx = (x - f.pos.X) * ca + (z - f.pos.Z) * sa
			local lz = -(x - f.pos.X) * sa + (z - f.pos.Z) * ca
			local len = f.length or f.radius * 2
			local along = 1 - smooth((math.abs(lx) - len * 0.6) / (len * 0.4))
			local across = smooth(1 - math.abs(lz) / f.radius)
			h += (f.height or 10) * along * across * (0.75 + 0.25 * math.noise(x * 0.05, z * 0.05, 4))
		end
	end
	return h
end

local function featureMaterial(spec: Spec, x: number, z: number): Enum.Material?
	for _, f in spec.features do
		if f.material then
			local d = math.sqrt((x - f.pos.X) ^ 2 + (z - f.pos.Z) ^ 2)
			if d <= f.radius then
				return f.material
			end
		end
	end
	return nil
end

-- Builds the island. Yields between tiles.
function IslandTerrain.build(spec: Spec)
	local pad = spec.radius * 0.45
	local minX = math.floor((spec.center.X - spec.radius - pad) / VOX)
	local maxX = math.ceil((spec.center.X + spec.radius + pad) / VOX)
	local minZ = math.floor((spec.center.Z - spec.radius - pad) / VOX)
	local maxZ = math.ceil((spec.center.Z + spec.radius + pad) / VOX)
	local nx, nz = maxX - minX, maxZ - minZ

	-- height map (columns are voxel centres), with a one-column border for slope lookups
	local heights: { [number]: { [number]: number } } = {}
	for i = -1, nx + 1 do
		local col = {}
		heights[i] = col
		local x = (minX + i + 0.5) * VOX
		for j = -1, nz + 1 do
			col[j] = heightAt(spec, x, (minZ + j + 0.5) * VOX)
		end
	end

	local ySlices = Y_LAYERS
	for ti = 0, math.ceil(nx / TILE) - 1 do
		for tj = 0, math.ceil(nz / TILE) - 1 do
			local i0, j0 = ti * TILE, tj * TILE
			local w = math.min(TILE, nx - i0)
			local d = math.min(TILE, nz - j0)
			if w > 0 and d > 0 then
				local mats: { { { Enum.Material } } } = {}
				local occs: { { { number } } } = {}
				for a = 1, w do
					local mx, ox = {}, {}
					mats[a], occs[a] = mx, ox
					local i = i0 + a - 1
					local wx = (minX + i + 0.5) * VOX
					for b = 1, ySlices do
						local my, oy = {}, {}
						mx[b], ox[b] = my, oy
						local yc = Y_MIN + (b - 0.5) * VOX
						local yb = yc - VOX / 2
						for c = 1, d do
							local j = j0 + c - 1
							local wz = (minZ + j + 0.5) * VOX
							local h = heights[i][j]
							local occ = math.clamp((h - yb) / VOX, 0, 1)
							if occ > 0.02 then
								local mat: Enum.Material
								if h - yb > VOX * 1.15 then
									-- below the surface layer
									mat = if h - yb > VOX * 3 then spec.deep else spec.rock
								else
									local slope = math.max(
										math.abs(heights[i + 1][j] - heights[i - 1][j]),
										math.abs(heights[i][j + 1] - heights[i][j - 1])
									) / (2 * VOX)
									local override = featureMaterial(spec, wx, wz)
									if override then
										mat = override
									elseif slope > 0.85 then
										mat = spec.rock
									elseif h < spec.seaLevel + 1.8 then
										mat = spec.shore
									elseif math.noise(wx * 0.045, wz * 0.045, spec.seed + 3) > 0.12 then
										mat = spec.ground2
									else
										mat = spec.ground
									end
								end
								my[c], oy[c] = mat, occ
							elseif yc < spec.seaLevel then
								my[c], oy[c] = Enum.Material.Water, 1
							else
								my[c], oy[c] = Enum.Material.Air, 0
							end
						end
					end
				end
				local min = Vector3.new((minX + i0) * VOX, Y_MIN, (minZ + j0) * VOX)
				local max = min + Vector3.new(w * VOX, ySlices * VOX, d * VOX)
				Terrain:WriteVoxels(Region3.new(min, max), VOX, mats, occs)
			end
		end
		task.wait()
	end
end

-- Water corridor connecting all islands (placed first; island voxels overwrite it where land exists).
function IslandTerrain.fillSea(minX: number, maxX: number, minZ: number, maxZ: number, seaLevel: number)
	local sx, sz = maxX - minX, maxZ - minZ
	local depth = 20
	Terrain:FillBlock(CFrame.new((minX + maxX) / 2, seaLevel - depth / 2, (minZ + maxZ) / 2), Vector3.new(sx, depth, sz), Enum.Material.Water)
end

IslandTerrain.heightAt = heightAt

return IslandTerrain
