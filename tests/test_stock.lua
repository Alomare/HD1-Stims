local stock = obsidian.module("src/stock")
local sync = obsidian.module("src/sync")

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

test("a drop starts full with four, takes one at a time down to none", function()
	local s = stock.new()
	eq(s.count, 4)
	eq(stock.full(s), true)
	for _ = 1, 4 do eq(stock.take(s), true) end
	eq(s.count, 0)
	eq(stock.take(s), false, "none left")
	eq(s.count, 0)
end)

test("an ammo box adds two, never past four", function()
	local s = stock.new()
	eq(stock.add(s), 0, "full")
	s.count = 3
	eq(stock.add(s), 1, "3 + 2 capped at 4")
	eq(s.count, 4)
	s.count = 1
	eq(stock.add(s), 2)
	eq(s.count, 3)
end)

test("sync text round trips and ignores other missions", function()
	local text = sync.encode(1234, { { id = 7, count = 3, used = 0 }, { id = 12, count = 0, used = 5 } })
	eq(text, "1234;7:3:0;12:0:5")
	local back = sync.decode(text, 1234)
	eq(#back, 2)
	eq(back[2].id, 12)
	eq(back[2].used, 5)
	eq(#sync.decode(text, 99), 0, "another mission")
	eq(#sync.decode(nil, 1234), 0)
	eq(#sync.decode("1234", 1234), 0, "no players")
	yes(#sync.encode(4294967295, { { id = 65535, count = 4, used = 999 }, { id = 65534, count = 4, used = 999 },
		{ id = 65533, count = 4, used = 999 }, { id = 65532, count = 4, used = 999 } }) <= 200, "fits member data")
end)

return T
