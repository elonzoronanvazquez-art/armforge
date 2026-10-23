-- SpatialGrid must answer exactly like a brute-force scan (it replaces one in RockService.near).
return function(t, u)
	local SpatialGrid = u:load("Logic/SpatialGrid")
	local Rng = u:load("Util/Rng")

	local function brute(points, x, z, radius)
		local out = {}
		for id, p in points do
			local dx, dz = p[1] - x, p[2] - z
			if dx * dx + dz * dz <= radius * radius then
				table.insert(out, id)
			end
		end
		table.sort(out)
		return out
	end

	local function sorted(list)
		table.sort(list)
		return list
	end

	t.test("matches a brute-force scan on random points and queries (including negative coordinates)", function()
		local rng = Rng.new(2024)
		local grid = SpatialGrid.new(32)
		local points = {}
		for id = 1, 300 do
			local x, z = rng:range(-900, 900), rng:range(-900, 900)
			points[id] = { x, z }
			grid:insert(id, x, z)
		end
		for _ = 1, 400 do
			local x, z, r = rng:range(-1000, 1000), rng:range(-1000, 1000), rng:range(1, 200)
			t.deepEq(sorted(grid:query(x, z, r)), brute(points, x, z, r))
		end
	end)

	t.test("points exactly on cell borders and exactly at the radius are included", function()
		local grid = SpatialGrid.new(10)
		grid:insert(1, 10, 10)
		grid:insert(2, 0, 0)
		grid:insert(3, -10, -10)
		t.deepEq(sorted(grid:query(10, 10, 0)), { 1 })
		t.deepEq(sorted(grid:query(0, 0, 14.15)), { 1, 2, 3 }, "the diagonal corners are 14.142 away")
		t.deepEq(sorted(grid:query(0, 0, 14.14)), { 2 }, "just short of the diagonal")
	end)

	t.test("remove and re-insert keep the index consistent", function()
		local grid = SpatialGrid.new(32)
		grid:insert(1, 5, 5)
		grid:insert(2, 500, 500)
		grid:remove(1)
		t.deepEq(grid:query(5, 5, 50), {})
		grid:insert(1, 480, 480)
		t.deepEq(sorted(grid:query(490, 490, 40)), { 1, 2 })
		grid:insert(1, -300, -300) -- moving an id replaces its old entry
		t.deepEq(grid:query(490, 490, 40), { 2 })
		t.deepEq(grid:query(-300, -300, 1), { 1 })
		grid:remove(99) -- unknown id is a no-op
		t.deepEq(sorted(grid:query(0, 0, 1000)), { 1, 2 })
	end)

	t.test("an empty grid and a zero radius are fine", function()
		local grid = SpatialGrid.new(32)
		t.deepEq(grid:query(0, 0, 100), {})
		grid:insert(7, 3, 4)
		t.deepEq(grid:query(3, 4, 0), { 7 })
		t.deepEq(grid:query(3.01, 4, 0), {})
	end)
end
