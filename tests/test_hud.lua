local hud = obsidian.module("src/hud")
local layout = obsidian.module("src/hud_layout")

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

test("the layout has four cells inside the texture, the lowest first", function()
	eq(#layout.cells, 4)
	for i, c in ipairs(layout.cells) do
		yes(c[1] >= 0 and c[2] <= 1 and c[1] < c[2], "cell " .. i .. " in range")
		if i > 1 then yes(c[2] <= layout.cells[i - 1][1], "cell " .. i .. " above cell " .. (i - 1)) end
	end
	yes(layout.top[2] <= layout.cells[4][1], "needle above the cells")
	yes(layout.bottom[1] >= layout.cells[1][2], "plunger below the cells")
end)

test("cells light up from the bottom, one per stim", function()
	local bands = hud.bands(2, 40)
	eq(#bands, 6)
	eq(bands[3][5], true, "lowest cell lit")
	eq(bands[4][5], true)
	eq(bands[5][5], false)
	eq(bands[6][5], false)
	eq(bands[1][5], true, "needle lit with stims left")
	local none = hud.bands(0, 40)
	eq(none[1][5], false, "needle grey with none")
	-- bands sit where their rows are: the plunger at the bottom, the needle at the top
	near(none[2][3], 0, 1e-9, "plunger from the bottom")
	near(none[1][3] + none[1][4], 40, 1e-9, "needle to the top")
end)

return T
