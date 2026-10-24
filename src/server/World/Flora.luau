--!strict
-- Flora and scatter props shared by the islands: trees, palms, bushes, vines, cacti, dead trunks and mossy rocks, all built from
-- primitives and varied by deterministic hashes (so a layout is stable between server starts). Everything decorative is anchored
-- and non-colliding except trunks, which block like real trees.

local Build = require(script.Parent.Build)

local Flora = {}

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles

export type Zone = { pos: Vector3, radius: number }

export type ScatterSpec = {
	center: Vector3,
	radius: number,
	count: number,
	seed: number,
	minY: number?, -- keep clear of water and beaches
	maxY: number?,
	avoid: { Zone }?,
	spacing: number?, -- minimum distance between two placed items
	tries: number?, -- attempts per item (default 6); raise it for narrow bands such as beaches
	make: (pos: Vector3, i: number, rnd: number) -> (),
}

local function pick(list: { Color3 }, h: number): Color3
	return list[1 + math.floor(h * #list) % #list]
end

local function lerpColor(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, t)
end

-- Places `count` items on random ground points inside a disc, skipping avoided zones, water and out-of-range heights.
function Flora.scatter(spec: ScatterSpec): number
	local placed: { Vector3 } = {}
	local minY = spec.minY or -0.2
	local maxY = spec.maxY or 60
	local spacing = spec.spacing or 0
	local attempts = spec.count * (spec.tries or 6)
	local avoid: { Zone } = spec.avoid or {}
	for i = 1, attempts do
		if #placed >= spec.count then
			break
		end
		local a = Build.hash(spec.seed + i, 1) * math.pi * 2
		local r = math.sqrt(Build.hash(spec.seed + i, 2)) * spec.radius
		local x, z = spec.center.X + math.cos(a) * r, spec.center.Z + math.sin(a) * r
		local ok = true
		for _, zone in avoid do
			local dx, dz = x - zone.pos.X, z - zone.pos.Z
			if dx * dx + dz * dz < zone.radius * zone.radius then
				ok = false
				break
			end
		end
		if ok and spacing > 0 then
			for _, p in placed do
				local dx, dz = x - p.X, z - p.Z
				if dx * dx + dz * dz < spacing * spacing then
					ok = false
					break
				end
			end
		end
		if ok then
			local y = Build.groundY(x, z)
			if y and y >= minY and y <= maxY then
				local pos = V3(x, y, z)
				table.insert(placed, pos)
				spec.make(pos, i, Build.hash(spec.seed + i, 3))
			end
		end
	end
	return #placed
end

-- Round leaf clump.
local function leaf(parent: Instance, pos: Vector3, size: Vector3, color: Color3, material: Enum.Material?)
	Build.part(parent, { name = "Leaves", size = size, cf = CF(pos), color = color, material = material or Enum.Material.LeafyGrass, shape = "Ball" })
end

export type TreeOpts = {
	trunk: Color3,
	leaves: { Color3 },
	leafMaterial: Enum.Material?,
	trunkMaterial: Enum.Material?,
}

-- A broadleaf tree: leaning trunk and a clump of leaf spheres.
function Flora.broadleaf(parent: Instance, pos: Vector3, height: number, seed: number, o: TreeOpts)
	local lean = (Build.hash(seed, 1) - 0.5) * 0.16
	local yaw = Build.hash(seed, 2) * math.pi * 2
	local trunkH = height * 0.62
	local d = math.clamp(height * 0.075, 0.7, 3.2)
	local base = CF(pos + V3(0, -0.4, 0)) * ANG(0, yaw, lean)
	Build.part(parent, {
		name = "Trunk",
		size = V3(trunkH + 0.4, d, d),
		cf = base * CF(0, (trunkH + 0.4) / 2, 0) * ANG(0, 0, math.pi / 2),
		color = o.trunk,
		material = o.trunkMaterial or Enum.Material.Wood,
		shape = "Cylinder",
		collide = true,
	})
	local top = (base * CF(0, trunkH, 0)).Position
	local r = height * 0.34
	for k = 1, 4 do
		local off = V3((Build.hash(seed, 10 + k) - 0.5) * r * 1.1, (Build.hash(seed, 20 + k) - 0.2) * r * 0.8, (Build.hash(seed, 30 + k) - 0.5) * r * 1.1)
		local s = r * (0.85 + Build.hash(seed, 40 + k) * 0.5)
		leaf(parent, top + off, V3(s, s * 0.82, s), pick(o.leaves, Build.hash(seed, 50 + k)), o.leafMaterial)
	end
end

-- Jungle giant: buttress roots, a straight trunk and a wide layered canopy. Optionally hangs vines from the canopy rim.
function Flora.jungleTree(parent: Instance, pos: Vector3, height: number, seed: number, o: TreeOpts, vines: boolean)
	local lean = (Build.hash(seed, 1) - 0.5) * 0.1
	local yaw = Build.hash(seed, 2) * math.pi * 2
	local trunkH = height * 0.74
	local d = math.clamp(height * 0.085, 1, 6)
	local base = CF(pos + V3(0, -1, 0)) * ANG(0, yaw, lean)
	Build.part(parent, {
		name = "Trunk",
		size = V3(trunkH + 1, d, d),
		cf = base * CF(0, (trunkH + 1) / 2, 0) * ANG(0, 0, math.pi / 2),
		color = o.trunk,
		material = o.trunkMaterial or Enum.Material.Wood,
		shape = "Cylinder",
		collide = true,
	})
	-- buttress roots flaring out at the base
	for k = 0, 3 do
		local a = yaw + k * math.pi / 2 + (Build.hash(seed, 60 + k) - 0.5) * 0.5
		Build.part(parent, {
			name = "Buttress",
			size = V3(0.5 + d * 0.25, d * 1.5, d * 1.3),
			cf = CF(pos + V3(math.cos(a) * d * 0.7, d * 0.55 - 0.6, math.sin(a) * d * 0.7)) * ANG(0, -a, 0.55),
			color = o.trunk,
			material = o.trunkMaterial or Enum.Material.Wood,
			shape = "Wedge",
		})
	end
	local top = (base * CF(0, trunkH, 0)).Position
	local r = height * 0.42
	for k = 1, 6 do
		local a = (k / 6) * math.pi * 2 + Build.hash(seed, 70 + k)
		local rr = r * (0.35 + Build.hash(seed, 80 + k) * 0.55)
		local off = V3(math.cos(a) * rr, (Build.hash(seed, 90 + k) - 0.3) * r * 0.35, math.sin(a) * rr)
		local s = r * (0.7 + Build.hash(seed, 100 + k) * 0.45)
		leaf(parent, top + off, V3(s, s * 0.5, s), pick(o.leaves, Build.hash(seed, 110 + k)), o.leafMaterial)
	end
	leaf(parent, top + V3(0, r * 0.2, 0), V3(r * 1.1, r * 0.7, r * 1.1), pick(o.leaves, Build.hash(seed, 120)), o.leafMaterial)
	if vines then
		for k = 1, 4 do
			local a = (k / 4) * math.pi * 2 + Build.hash(seed, 130 + k)
			local rr = r * 0.8
			local from = top + V3(math.cos(a) * rr, -r * 0.12, math.sin(a) * rr)
			Flora.vine(parent, from, math.min(trunkH * 0.7, 8 + Build.hash(seed, 140 + k) * 14), seed + k, Color3.fromRGB(58, 98, 52))
		end
	end
end

-- A slim young tree (small trees in the sketch).
function Flora.sapling(parent: Instance, pos: Vector3, height: number, seed: number, o: TreeOpts)
	local trunkH = height * 0.7
	Build.part(parent, {
		name = "Trunk",
		size = V3(trunkH + 0.4, 0.55, 0.55),
		cf = CF(pos + V3(0, trunkH / 2 - 0.2, 0)) * ANG(0, 0, math.pi / 2),
		color = o.trunk,
		material = o.trunkMaterial or Enum.Material.Wood,
		shape = "Cylinder",
	})
	local s = height * 0.55
	leaf(parent, pos + V3(0, trunkH + s * 0.12, 0), V3(s, s * 0.9, s), pick(o.leaves, Build.hash(seed, 3)), o.leafMaterial)
end

-- Palm: curved trunk of three segments and a crown of drooping fronds.
function Flora.palm(parent: Instance, pos: Vector3, height: number, seed: number, frond: Color3?)
	local yaw = Build.hash(seed, 1) * math.pi * 2
	local bend = 0.1 + Build.hash(seed, 2) * 0.12
	local cf = CF(pos + V3(0, -0.4, 0)) * ANG(0, yaw, 0)
	local segH = height / 3
	local trunkColor = lerpColor(Color3.fromRGB(128, 98, 66), Color3.fromRGB(104, 78, 52), Build.hash(seed, 3))
	for k = 1, 3 do
		cf = cf * ANG(0, 0, bend)
		Build.part(parent, {
			name = "Trunk",
			size = V3(segH + 0.3, 1.3 - k * 0.2, 1.3 - k * 0.2),
			cf = cf * CF(0, segH / 2, 0) * ANG(0, 0, math.pi / 2),
			color = trunkColor,
			material = Enum.Material.Wood,
			shape = "Cylinder",
			collide = k == 1,
		})
		cf = cf * CF(0, segH, 0)
	end
	local top = cf.Position
	local green = frond or Color3.fromRGB(70, 122, 58)
	for k = 0, 6 do
		local a = (k / 7) * math.pi * 2 + yaw
		Build.part(parent, {
			name = "Frond",
			size = V3(1.7, 0.18, 8.4),
			cf = CF(top) * ANG(0, -a, 0) * CF(0, 0.2, 4.0) * ANG(math.rad(18), 0, 0),
			color = lerpColor(green, Color3.fromRGB(110, 150, 70), Build.hash(seed, 20 + k) * 0.6),
			material = Enum.Material.LeafyGrass,
		})
	end
	for k = 1, 2 do
		Build.part(parent, { name = "Coconut", size = V3(1, 1, 1), cf = CF(top + V3(k * 0.7 - 1.1, -0.9, 0.4)), color = Color3.fromRGB(86, 62, 42), material = Enum.Material.Wood, shape = "Ball" })
	end
end

-- Low bush: a few squashed spheres.
function Flora.bush(parent: Instance, pos: Vector3, size: number, seed: number, leaves: { Color3 }, flower: Color3?)
	for k = 1, 3 do
		local s = size * (0.7 + Build.hash(seed, k) * 0.5)
		leaf(parent, pos + V3((Build.hash(seed, 10 + k) - 0.5) * size * 0.8, s * 0.32, (Build.hash(seed, 20 + k) - 0.5) * size * 0.8), V3(s, s * 0.7, s), pick(leaves, Build.hash(seed, 30 + k)))
	end
	if flower and Build.hash(seed, 40) > 0.45 then
		for k = 1, 3 do
			Build.part(parent, { name = "Flower", size = V3(0.4, 0.4, 0.4), cf = CF(pos + V3((Build.hash(seed, 50 + k) - 0.5) * size, size * 0.65, (Build.hash(seed, 60 + k) - 0.5) * size)), color = flower, material = Enum.Material.SmoothPlastic, shape = "Ball" })
		end
	end
end

-- Fern: a fan of long thin leaves.
function Flora.fern(parent: Instance, pos: Vector3, size: number, seed: number, color: Color3)
	local yaw = Build.hash(seed, 1) * math.pi
	for k = 0, 5 do
		local a = yaw + (k / 6) * math.pi * 2
		Build.part(parent, {
			name = "Frond",
			size = V3(0.7, 0.12, size),
			cf = CF(pos + V3(0, 0.2, 0)) * ANG(0, -a, 0) * CF(0, size * 0.18, size * 0.46) * ANG(math.rad(-34), 0, 0),
			color = lerpColor(color, Color3.fromRGB(120, 170, 80), Build.hash(seed, 2 + k) * 0.5),
			material = Enum.Material.LeafyGrass,
		})
	end
end

-- A hanging vine: a thin cord with a few leaves, dangling from `from` downward by `length`.
function Flora.vine(parent: Instance, from: Vector3, length: number, seed: number, color: Color3)
	local sway = (Build.hash(seed, 1) - 0.5) * 0.12
	Build.part(parent, {
		name = "Vine",
		size = V3(length, 0.28, 0.28),
		cf = CF(from + V3(0, -length / 2, 0)) * ANG(0, 0, math.pi / 2 + sway),
		color = color,
		material = Enum.Material.Grass,
		shape = "Cylinder",
	})
	local n = math.max(2, math.floor(length / 4))
	for k = 1, n do
		local y = -length * (k / (n + 1))
		Build.part(parent, {
			name = "VineLeaf",
			size = V3(1.5, 0.12, 1),
			cf = CF(from + V3(sway * -y * 0.4, y, 0)) * ANG(0, Build.hash(seed, 10 + k) * 6, 0.5 * (if k % 2 == 0 then 1 else -1)),
			color = lerpColor(color, Color3.fromRGB(110, 170, 80), 0.4),
			material = Enum.Material.LeafyGrass,
		})
	end
end

-- Mossy rock: a grey boulder cluster with a green moss cap.
function Flora.mossRock(parent: Instance, pos: Vector3, size: number, seed: number, stone: Color3?, moss: Color3?)
	local grey = stone or Color3.fromRGB(104, 106, 100)
	local green = moss or Color3.fromRGB(72, 116, 60)
	local yaw = Build.hash(seed, 1) * math.pi * 2
	Build.part(parent, { name = "Boulder", size = V3(size, size * 0.7, size * 0.9), cf = CF(pos + V3(0, size * 0.22, 0)) * ANG(0.1, yaw, 0.08), color = grey, material = Enum.Material.Rock, shape = "Ball", collide = true })
	Build.part(parent, { name = "Moss", size = V3(size * 0.92, size * 0.34, size * 0.8), cf = CF(pos + V3(0, size * 0.5, 0)) * ANG(0.1, yaw, 0.08), color = green, material = Enum.Material.Grass, shape = "Ball" })
	if Build.hash(seed, 2) > 0.4 then
		local s2 = size * 0.5
		Build.part(parent, { name = "Boulder", size = V3(s2, s2 * 0.8, s2), cf = CF(pos + V3(size * 0.6, s2 * 0.2, size * 0.25)) * ANG(0, yaw, 0), color = grey, material = Enum.Material.Rock, shape = "Ball", collide = true })
		Build.part(parent, { name = "Moss", size = V3(s2 * 0.9, s2 * 0.3, s2 * 0.8), cf = CF(pos + V3(size * 0.6, s2 * 0.5, size * 0.25)), color = green, material = Enum.Material.Grass, shape = "Ball" })
	end
end

-- Saguaro-style cactus with up to two arms.
function Flora.cactus(parent: Instance, pos: Vector3, height: number, seed: number)
	local green = lerpColor(Color3.fromRGB(86, 120, 70), Color3.fromRGB(104, 138, 80), Build.hash(seed, 1))
	local d = math.clamp(height * 0.16, 0.9, 2)
	Build.part(parent, { name = "Cactus", size = V3(height + 0.4, d, d), cf = CF(pos + V3(0, height / 2 - 0.2, 0)) * ANG(0, 0, math.pi / 2), color = green, material = Enum.Material.Grass, shape = "Cylinder", collide = true })
	Build.part(parent, { name = "CactusTop", size = V3(d, d, d), cf = CF(pos + V3(0, height, 0)), color = green, material = Enum.Material.Grass, shape = "Ball" })
	local arms = 1 + math.floor(Build.hash(seed, 2) * 2)
	for k = 1, arms do
		local side = if k == 1 then 1 else -1
		local yaw = Build.hash(seed, 3) * math.pi * 2
		local y = height * (0.38 + 0.14 * k)
		local at = CF(pos) * ANG(0, yaw, 0)
		local reach = d * 1.6
		Build.part(parent, { name = "CactusArm", size = V3(reach + d, d * 0.7, d * 0.7), cf = at * CF(side * (reach / 2 + d * 0.3), y, 0) * ANG(0, 0, 0), color = green, material = Enum.Material.Grass, shape = "Cylinder" })
		Build.part(parent, { name = "CactusArmUp", size = V3(height * 0.3, d * 0.7, d * 0.7), cf = at * CF(side * (reach + d * 0.4), y + height * 0.15, 0) * ANG(0, 0, math.pi / 2), color = green, material = Enum.Material.Grass, shape = "Cylinder" })
	end
end

-- Bleached, leafless trunk with a few snapped branches.
function Flora.deadTree(parent: Instance, pos: Vector3, height: number, seed: number)
	local wood = lerpColor(Color3.fromRGB(150, 128, 100), Color3.fromRGB(112, 92, 72), Build.hash(seed, 1))
	local yaw = Build.hash(seed, 2) * math.pi * 2
	local lean = (Build.hash(seed, 3) - 0.5) * 0.3
	local base = CF(pos + V3(0, -0.4, 0)) * ANG(0, yaw, lean)
	Build.part(parent, { name = "Trunk", size = V3(height, 1.1, 1.1), cf = base * CF(0, height / 2, 0) * ANG(0, 0, math.pi / 2), color = wood, material = Enum.Material.Wood, shape = "Cylinder", collide = true })
	for k = 1, 3 do
		local y = height * (0.45 + 0.17 * k)
		local len = height * (0.32 - 0.05 * k)
		local side = if k % 2 == 0 then 1 else -1
		Build.part(parent, { name = "Branch", size = V3(len, 0.5, 0.5), cf = base * CF(side * len * 0.3, y, 0) * ANG(0, k, side * 0.9) , color = wood, material = Enum.Material.Wood, shape = "Cylinder" })
	end
end

-- Short dry grass / reeds: a tuft of thin blades.
function Flora.tuft(parent: Instance, pos: Vector3, height: number, seed: number, color: Color3)
	for k = 1, 4 do
		local a = Build.hash(seed, k) * math.pi * 2
		Build.part(parent, {
			name = "Blade",
			size = V3(height, 0.18, 0.18),
			cf = CF(pos + V3(math.cos(a) * 0.5, height / 2 - 0.1, math.sin(a) * 0.5)) * ANG(0, 0, math.pi / 2 + (Build.hash(seed, 10 + k) - 0.5) * 0.35),
			color = lerpColor(color, Color3.fromRGB(190, 190, 110), Build.hash(seed, 20 + k) * 0.5),
			material = Enum.Material.Grass,
			shape = "Cylinder",
		})
	end
end

return Flora
