--!strict
-- Uniform grid over the XZ plane for "which ids are near this point" queries. Ids are inserted at a fixed position
-- (rocks never move horizontally), so a query only has to look at the few cells around the point instead of
-- scanning every id. The grid is a pre-filter: callers still apply their exact distance test to the candidates.

local SpatialGrid = {}
SpatialGrid.__index = SpatialGrid

export type Grid = typeof(setmetatable(
	{} :: {
		cellSize: number,
		cells: { [number]: { [number]: boolean } },
		where: { [number]: number },
		xs: { [number]: number },
		zs: { [number]: number },
	},
	SpatialGrid
))

local OFFSET = 32768 -- keeps cell indices positive for the packed key (supports +-32768 cells per axis)

local function cellKey(ix: number, iz: number): number
	return (ix + OFFSET) * 65536 + (iz + OFFSET)
end

function SpatialGrid.new(cellSize: number): Grid
	assert(cellSize > 0, "cellSize must be positive")
	return setmetatable({
		cellSize = cellSize,
		cells = {},
		where = {},
		xs = {},
		zs = {},
	}, SpatialGrid)
end

function SpatialGrid.insert(self: Grid, id: number, x: number, z: number)
	if self.where[id] ~= nil then
		SpatialGrid.remove(self, id)
	end
	local key = cellKey(math.floor(x / self.cellSize), math.floor(z / self.cellSize))
	local cell = self.cells[key]
	if not cell then
		cell = {}
		self.cells[key] = cell
	end
	cell[id] = true
	self.where[id] = key
	self.xs[id] = x
	self.zs[id] = z
end

function SpatialGrid.remove(self: Grid, id: number)
	local key = self.where[id]
	if key == nil then
		return
	end
	local cell = self.cells[key]
	if cell then
		cell[id] = nil
		if next(cell) == nil then
			self.cells[key] = nil
		end
	end
	self.where[id] = nil
	self.xs[id] = nil
	self.zs[id] = nil
end

-- Ids whose stored position is within `radius` of (x, z) horizontally (exact circle, not just cell membership).
function SpatialGrid.query(self: Grid, x: number, z: number, radius: number): { number }
	local out: { number } = {}
	local size = self.cellSize
	local r2 = radius * radius
	local ix0, ix1 = math.floor((x - radius) / size), math.floor((x + radius) / size)
	local iz0, iz1 = math.floor((z - radius) / size), math.floor((z + radius) / size)
	for ix = ix0, ix1 do
		for iz = iz0, iz1 do
			local cell = self.cells[cellKey(ix, iz)]
			if cell then
				for id in cell do
					local dx, dz = self.xs[id] - x, self.zs[id] - z
					if dx * dx + dz * dz <= r2 then
						table.insert(out, id)
					end
				end
			end
		end
	end
	return out
end

return SpatialGrid
