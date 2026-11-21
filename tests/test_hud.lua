local hud = obsidian.module("src/hud")
local layout = obsidian.module("src/hud_layout")

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

test("each maximum has its own syringe with that many charges inside the texture, top first", function()
	for n = 1, 4 do
		local s = layout[n]
		eq(#s.segments, n, "charges of " .. n)
		eq(s.sprite, "stims_syringe" .. n)
		for i, c in ipairs(s.segments) do
			yes(c[1] >= 0 and c[2] <= 1 and c[1] < c[2], n .. ": charge " .. i .. " in range")
			if i > 1 then yes(c[1] >= s.segments[i - 1][2], n .. ": charge " .. i .. " below charge " .. (i - 1)) end
		end
		near(s.segments[1][1], 0, 1e-9, "the tip from the top")
		near(s.segments[n][2], 1, 1e-9, "the end to the bottom")
	end
	eq(hud.syringe(9), layout[4], "a maximum past 4 takes the four")
end)

test("charges grey out from the top, one per stim used", function()
	local lit = function(count, max)
		local out = {}
		for i, b in ipairs(hud.bands(count, 40, max)) do out[i] = b[5] and "x" or "." end
		return table.concat(out)
	end
	eq(lit(4, 4), "xxxx")
	eq(lit(3, 4), ".xxx", "first stim greys the tip")
	eq(lit(1, 4), "...x", "the end is the last")
	eq(lit(0, 4), "....")
	eq(lit(2, 3), ".xx")
	eq(lit(1, 2), ".x")
	eq(lit(1, 1), "x")
	eq(lit(0, 1), ".")
	local b = hud.bands(4, 40, 4)
	near(b[4][3], 0, 1e-9, "end from the bottom")
	near(b[1][3] + b[1][4], 40, 1e-9, "tip to the top")
end)

return T
