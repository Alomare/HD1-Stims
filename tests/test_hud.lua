local hud = obsidian.module("src/hud")
local layout = obsidian.module("src/hud_layout")

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

test("the layout has four charges inside the texture, top first", function()
	eq(#layout.segments, 4)
	for i, c in ipairs(layout.segments) do
		yes(c[1] >= 0 and c[2] <= 1 and c[1] < c[2], "charge " .. i .. " in range")
		if i > 1 then yes(c[1] >= layout.segments[i - 1][2], "charge " .. i .. " below charge " .. (i - 1)) end
	end
	near(layout.segments[1][1], 0, 1e-9, "the tip from the top")
	near(layout.segments[4][2], 1, 1e-9, "the end to the bottom")
end)

test("charges grey out from the top, one per stim used", function()
	local lit = function(count)
		local out = {}
		for i, b in ipairs(hud.bands(count, 40)) do out[i] = b[5] and "x" or "." end
		return table.concat(out)
	end
	eq(lit(4), "xxxx")
	eq(lit(3), ".xxx", "first stim greys the tip")
	eq(lit(1), "...x", "the end is the last")
	eq(lit(0), "....")
	-- bands sit where their rows are: the end at the bottom, the tip at the top
	local b = hud.bands(4, 40)
	near(b[4][3], 0, 1e-9, "end from the bottom")
	near(b[1][3] + b[1][4], 40, 1e-9, "tip to the top")
end)

return T
