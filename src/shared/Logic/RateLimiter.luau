--!strict
-- Token-bucket rate limiter. One bucket per (player, action). `take` returns false when the caller is spamming.

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type Bucket = { tokens: number, last: number, rate: number, burst: number }
export type Limiter = typeof(setmetatable({} :: { buckets: { [string]: Bucket } }, RateLimiter))

function RateLimiter.new(): Limiter
	return setmetatable({ buckets = {} }, RateLimiter)
end

-- Consumes one token if available. rate = tokens regained per second, burst = bucket size.
function RateLimiter.take(self: Limiter, key: string, rate: number, burst: number, now: number): boolean
	local b = self.buckets[key]
	if not b then
		b = { tokens = burst, last = now, rate = rate, burst = burst }
		self.buckets[key] = b
	end
	b.tokens = math.min(burst, b.tokens + (now - b.last) * rate)
	b.last = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

function RateLimiter.clear(self: Limiter, prefix: string)
	for key in self.buckets do
		if string.sub(key, 1, #prefix) == prefix then
			self.buckets[key] = nil
		end
	end
end

return RateLimiter
