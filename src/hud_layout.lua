-- Written by tools/build_hud.py. Do not edit.
-- The syringe texture's charges as bands of v (shares of its height from the top), top first: the
-- tip, two barrel cells and the end. The first stim used greys out the tip.
return {
	sprite = "stims_syringe",
	aspect = 0.3125, -- width over height
	segments = {
		{ 0.0, 0.39062 },
		{ 0.42578, 0.60156 },
		{ 0.63672, 0.8125 },
		{ 0.84766, 1.0 },
	},
}
