-- Written by tools/build_hud.py. Do not edit.
-- The syringe texture's bands as shares of its height from the top (v), stim 1 the lowest cell.
return {
	sprite = "stims_syringe",
	aspect = 0.3125, -- width over height
	top = { 0, 0.39062 }, -- the needle and hub
	bottom = { 0.84766, 1 }, -- the flange and plunger
	cells = {
		{ 0.75781, 0.84766 },
		{ 0.63672, 0.72656 },
		{ 0.51562, 0.60156 },
		{ 0.39062, 0.47656 },
	},
}
