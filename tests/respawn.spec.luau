-- RespawnGuard: the footprint test that keeps a respawning rock from shoving or trapping a player.
local roblox = require("@lune/roblox")

return function(t, u)
	local Guard = u:load("Logic/RespawnGuard")
	local V = roblox.Vector3
	local base = V.new(100, 10, 50)

	t.test("a player standing inside the footprint blocks the respawn", function()
		t.truthy(Guard.blocked(base, 5, 8, { V.new(102, 13, 51) }, 3))
	end)

	t.test("the clearance ring blocks too, beyond it does not", function()
		t.truthy(Guard.blocked(base, 5, 8, { V.new(107.9, 13, 50) }, 3), "just inside radius + clearance")
		t.eq(Guard.blocked(base, 5, 8, { V.new(108.2, 13, 50) }, 3), false, "just outside")
	end)

	t.test("players far above or far below the rock do not block it", function()
		t.eq(Guard.blocked(base, 5, 8, { V.new(100, 80, 50) }, 3), false)
		t.eq(Guard.blocked(base, 5, 8, { V.new(100, -60, 50) }, 3), false)
	end)

	t.test("any one of several players is enough; none means clear", function()
		t.truthy(Guard.blocked(base, 5, 8, { V.new(500, 10, 500), V.new(101, 12, 50) }, 3))
		t.eq(Guard.blocked(base, 5, 8, { V.new(500, 10, 500), V.new(-40, 12, 50) }, 3), false)
		t.eq(Guard.blocked(base, 5, 8, {}, 3), false)
	end)

	t.test("a taller rock extends the vertical window", function()
		local above = V.new(100, 10 + 30, 50)
		t.eq(Guard.blocked(base, 5, 8, { above }, 3), false)
		t.truthy(Guard.blocked(base, 5, 30, { above }, 3))
	end)
end
