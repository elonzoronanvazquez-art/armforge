--!strict
-- Terrain-hugging strips: spiral roads up a mountain or volcano, and flows (lava, water) laid down a slope.

local Build = require(script.Parent.Build)

local Road = {}

local V3 = Vector3.new
local CF = CFrame.new

-- A strip of material laid along the terrain between two points.
function Road.strip(parent: Instance, name: string, a: Vector3, b: Vector3, width: number, thick: number, color: Color3, material: Enum.Material, collide: boolean?): BasePart
	local len = (b - a).Magnitude + 0.5
	return Build.part(parent, { name = name, size = V3(width, thick, len), cf = CFrame.lookAt((a + b) / 2, b), color = color, material = material, collide = collide })
end

export type SpiralOpts = {
	center: Vector3,
	outer: number, -- radius where the road starts (at the foot)
	inner: number, -- radius where it ends (at the top)
	turns: number,
	steps: number,
	theta0: number, -- start angle, radians (pi/2 = toward +Z)
	clockwise: boolean?, -- viewed from above with +Z south; default true
	width: number?,
	colors: { Color3 },
	material: Enum.Material,
	lampColor: Color3,
	lampEvery: number?,
}

-- Lays a spiral road onto the terrain and returns its centre points (useful to keep flora off it).
function Road.spiral(parent: Instance, o: SpiralOpts): { Vector3 }
	local pts: { Vector3 } = {}
	local dirSign = if o.clockwise == false then 1 else -1
	for i = 0, o.steps do
		local s = i / o.steps
		local r = o.outer - (o.outer - o.inner) * s
		local theta = o.theta0 + dirSign * math.pi * 2 * o.turns * s
		local x, z = o.center.X + math.cos(theta) * r, o.center.Z + math.sin(theta) * r
		table.insert(pts, V3(x, (Build.groundY(x, z) or 0.6) + 0.35, z))
	end
	local every = o.lampEvery or 6
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		Road.strip(parent, "RoadSlab", a, b, o.width or 6, 0.5, o.colors[1 + i % #o.colors], o.material)
		if every > 0 and i % every == 0 then
			local base = a + (b - a).Unit:Cross(Vector3.yAxis).Unit * ((o.width or 6) / 2 + 0.8)
			Build.part(parent, { name = "LampPost", size = V3(0.5, 5, 0.5), cf = CF(base + V3(0, 2.5, 0)), color = Color3.fromRGB(70, 74, 86), material = Enum.Material.Metal })
			local lamp = Build.part(parent, { name = "Lamp", size = V3(1.1, 1.1, 1.1), cf = CF(base + V3(0, 5.4, 0)), color = o.lampColor, neon = true, shape = "Ball" })
			Build.light(lamp, o.lampColor, 1, 20)
		end
	end
	return pts
end

-- Samples the ground from `from` along a flat direction and returns the points of a flow until it meets water or `maxLength`.
function Road.flow(from: Vector3, dir: Vector3, maxLength: number, step: number): { Vector3 }
	local flat = V3(dir.X, 0, dir.Z).Unit
	local pts: { Vector3 } = {}
	local d = 0
	while d <= maxLength do
		local x, z = from.X + flat.X * d, from.Z + flat.Z * d
		local y = Build.groundY(x, z)
		if y == nil or y < -1 then
			break
		end
		table.insert(pts, V3(x, y, z))
		d += step
	end
	return pts
end

return Road
