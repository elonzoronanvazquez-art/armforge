--!strict
-- Minimal synchronous signal used by the client store and UI. (Roblox's own BindableEvent is deliberately avoided: it
-- copies arguments and defers delivery, which makes UI state lag by a frame.)

export type Connection = { Disconnect: (self: Connection) -> (), connected: boolean }
export type Signal<T...> = {
	connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	fire: (self: Signal<T...>, T...) -> (),
}

local Signal = {}
Signal.__index = Signal

function Signal.new<T...>(): Signal<T...>
	return setmetatable({ handlers = {} }, Signal) :: any
end

function Signal.connect(self: any, fn: (...any) -> ()): Connection
	local conn = { connected = true, fn = fn } :: any
	function conn.Disconnect(c: any)
		c.connected = false
		local list = self.handlers
		local i = table.find(list, c)
		if i then
			table.remove(list, i)
		end
	end
	table.insert(self.handlers, conn)
	return conn
end

function Signal.fire(self: any, ...: any)
	for _, conn: any in table.clone(self.handlers) do
		if conn.connected then
			task.spawn(conn.fn, ...)
		end
	end
end

return Signal
