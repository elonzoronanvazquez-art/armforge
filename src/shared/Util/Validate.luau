--!strict
-- Argument validation helpers for remote handlers. Every value that crosses the network is untrusted.

local Validate = {}

function Validate.number(v: any, lo: number?, hi: number?): number?
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return nil
	end
	if (lo and v < lo) or (hi and v > hi) then
		return nil
	end
	return v
end

function Validate.int(v: any, lo: number?, hi: number?): number?
	local n = Validate.number(v, lo, hi)
	if n == nil or n % 1 ~= 0 then
		return nil
	end
	return n
end

function Validate.string(v: any, maxLen: number?): string?
	if type(v) ~= "string" or #v > (maxLen or 64) then
		return nil
	end
	return v
end

function Validate.id(v: any): string?
	local s = Validate.string(v, 32)
	if s and string.match(s, "^[%w_]+$") then
		return s
	end
	return nil
end

function Validate.bool(v: any): boolean?
	if type(v) == "boolean" then
		return v
	end
	return nil
end

function Validate.table(v: any): { [any]: any }?
	if type(v) == "table" then
		return v
	end
	return nil
end

return Validate
