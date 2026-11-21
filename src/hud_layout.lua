-- Written by tools/build_hud.py. Do not edit.
-- The syringe for each maximum of stims (1 to 4): its sprite, and its charges as bands of v (shares
-- of its height from the top), top first. The first stim used greys out the top charge.
return {
	aspect = 0.3125, -- width over height
	[1] = { sprite = "stims_syringe1", segments = {
		{ 0.0, 1.0 },
	} },
	[2] = { sprite = "stims_syringe2", segments = {
		{ 0.0, 0.39062 },
		{ 0.42578, 1.0 },
	} },
	[3] = { sprite = "stims_syringe3", segments = {
		{ 0.0, 0.39062 },
		{ 0.42578, 0.8125 },
		{ 0.84766, 1.0 },
	} },
	[4] = { sprite = "stims_syringe4", segments = {
		{ 0.0, 0.39062 },
		{ 0.42578, 0.60156 },
		{ 0.63672, 0.8125 },
		{ 0.84766, 1.0 },
	} },
}
