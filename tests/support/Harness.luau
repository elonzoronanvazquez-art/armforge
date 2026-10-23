-- Minimal test harness: t.test(name, fn) plus assertion helpers that raise on failure.

local Harness = {}

local function deepEqual(a, b)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function show(value)
	if type(value) == "table" then
		local parts = {}
		for k, v in value do
			table.insert(parts, tostring(k) .. "=" .. show(v))
		end
		table.sort(parts)
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(value)
end

function Harness.new(suiteName)
	local tests = {}
	local t = { suiteName = suiteName, tests = tests }

	function t.test(name, fn)
		table.insert(tests, { name = name, fn = fn })
	end

	function t.eq(actual, expected, message)
		if actual ~= expected then
			error(`{message or "eq"}: expected {show(expected)}, got {show(actual)}`, 2)
		end
	end

	function t.deepEq(actual, expected, message)
		if not deepEqual(actual, expected) then
			error(`{message or "deepEq"}: expected {show(expected)}, got {show(actual)}`, 2)
		end
	end

	function t.near(actual, expected, tolerance, message)
		if math.abs(actual - expected) > (tolerance or 1e-9) then
			error(`{message or "near"}: expected {expected} +/- {tolerance or 1e-9}, got {actual}`, 2)
		end
	end

	function t.truthy(value, message)
		if not value then
			error(`{message or "truthy"}: got {show(value)}`, 2)
		end
	end

	function t.lt(a, b, message)
		if not (a < b) then
			error(`{message or "lt"}: expected {a} < {b}`, 2)
		end
	end

	function t.lte(a, b, message)
		if not (a <= b) then
			error(`{message or "lte"}: expected {a} <= {b}`, 2)
		end
	end

	function t.throws(fn, pattern, message)
		local ok, err = pcall(fn)
		if ok then
			error(`{message or "throws"}: expected an error`, 2)
		end
		if pattern and not string.find(tostring(err), pattern, 1, true) then
			error(`{message or "throws"}: error '{tostring(err)}' does not contain '{pattern}'`, 2)
		end
	end

	return t
end

return Harness
