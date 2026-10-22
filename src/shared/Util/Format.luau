--!strict
-- Number / time formatting shared by the UI and effects.

local Format = {}

-- 1234 -> "1,234"
function Format.commas(n: number): string
	local s = tostring(math.floor(n + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- Compact: 12345 -> "12.3K", 4.2e6 -> "4.2M"
function Format.compact(n: number): string
	local abs = math.abs(n)
	if abs >= 1e12 then
		return string.format("%.1fT", n / 1e12)
	elseif abs >= 1e9 then
		return string.format("%.1fB", n / 1e9)
	elseif abs >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif abs >= 1e4 then
		return string.format("%.1fK", n / 1e3)
	end
	return Format.commas(n)
end

-- 75 -> "1:15", 3700 -> "1:01:40"
function Format.clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds + 0.5))
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

function Format.percent(fraction: number, decimals: number?): string
	local d = decimals or 0
	return string.format("%." .. d .. "f%%", fraction * 100)
end

return Format
