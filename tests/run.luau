-- Test runner. Usage (from repo root): lune run tests/run [filter]
-- Discovers tests/*.spec.luau; each spec returns function(t, universe).

local fs = require("@lune/fs")
local process = require("@lune/process")
local Harness = require("./support/Harness")
local Loader = require("./support/Loader")

if not fs.isDir("src/shared") then
	print("Run the tests from the repository root (src/shared not found).")
	process.exit(2)
end

local filter = process.args[1]
local files = {}
for _, name in fs.readDir("tests") do
	if name:match("%.spec%.luau$") and (filter == nil or name:find(filter, 1, true)) then
		table.insert(files, name)
	end
end
table.sort(files)

local passed, failed = 0, 0
local failures = {}

for _, file in files do
	local module = (file:gsub("%.luau$", ""))
	local spec = require("./" .. module)
	local t = Harness.new(module)
	spec(t, Loader.new())
	for _, test in t.tests do
		local ok, err = xpcall(test.fn, function(e)
			return tostring(e) .. "\n" .. debug.traceback("", 2)
		end)
		if ok then
			passed += 1
			print(`  PASS  {module} :: {test.name}`)
		else
			failed += 1
			table.insert(failures, `{module} :: {test.name}\n{err}`)
			print(`  FAIL  {module} :: {test.name}`)
		end
	end
end

print()
for _, failure in failures do
	print(failure)
	print()
end
print(`{passed} passed, {failed} failed, {passed + failed} total`)
process.exit(if failed > 0 or passed == 0 then 1 else 0)
