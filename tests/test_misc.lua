local stim = obsidian.module("src/stim")
local sound = obsidian.module("src/sound")
local sounds = obsidian.module("src/sounds")

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

test("a stim starts on foot and holds through firing, never while downed", function()
	eq(stim.can_start("CharacterStateIdle", false), true)
	eq(stim.can_start("CharacterStateSprint", false), true)
	eq(stim.can_start("CharacterStateDodge", false), false)
	eq(stim.can_start("CharacterStateReload", false), false)
	eq(stim.can_start("CharacterStateIdle", true), false, "downed")
	eq(stim.can_keep("CharacterStateAimWalkFire", false), true)
	eq(stim.can_keep("CharacterStateKnockedDown", false), false)
	eq(stim.can_keep("CharacterStateMelee", false), false)
end)

test("the boost heals 80 a second up to the maximum", function()
	near(stim.heal_step(50, 100, 0.1), 8)
	near(stim.heal_step(97, 100, 0.1), 3)
	eq(stim.heal_step(100, 100, 0.1), 0)
	eq(stim.heal_step(nil, 100, 0.1), 0)
end)

test("the sounds are plain mono 16-bit WAVs of one format", function()
	yes(#sounds >= 1)
	local c, r, b = sound.format(sounds[1])
	eq(c, 1) eq(b, 16)
	for i, s in ipairs(sounds) do
		eq(s:sub(1, 4), "RIFF", "variant " .. i)
		eq(s:sub(37, 40), "data", "variant " .. i)
		local c2, r2, b2 = sound.format(s)
		eq(c2, c) eq(r2, r) eq(b2, b)
	end
end)

test("volume scales samples and keeps the header", function()
	local head = sounds[1]:sub(1, 44)
	local wav = head .. string.char(0, 64, 0, 192) -- 16384, -16384
	local half = sound.scaled(wav, 0.5)
	eq(half:sub(1, 44), head)
	eq(half:byte(46), 32)
	eq(half:byte(48), 224)
	eq(sound.gain(0), 0)
	near(sound.gain(1), sound.GAIN)
end)

test("the manifest lists every module", function()
	local f = assert(io.open("obsidian.json", "r"))
	local manifest = f:read("*a")
	f:close()
	for _, m in ipairs({ "stim", "stock", "sync", "anim", "pose", "hud", "hud_layout", "sound", "sounds" }) do
		yes(manifest:find('"src/' .. m .. '.lua"', 1, true), "src/" .. m .. ".lua in the manifest")
	end
end)

return T
