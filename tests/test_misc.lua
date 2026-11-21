local stim = obsidian.module("src/stim")
local sound = obsidian.module("src/sound")
local sounds = obsidian.module("src/sounds")

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

test("a stim starts on foot or prone and holds through firing", function()
	eq(stim.can_start("CharacterStateIdle", false), true)
	eq(stim.can_start("CharacterStateSprint", false), true)
	eq(stim.can_start("CharacterStateCrawl", false), true, "prone")
	eq(stim.can_start("CharacterStateDodge", false), true, "down after a dive")
	eq(stim.can_start("CharacterStateReload", false), false)
	eq(stim.can_keep("CharacterStateAimWalkFire", false), true)
	eq(stim.can_keep("CharacterStateKnockedDown", false), false)
	eq(stim.can_keep("CharacterStateMelee", false), false)
end)

test("a downed stim follows the option", function()
	stim.allow_downed = true
	eq(stim.can_start("CharacterStateDownedIdle", true), true)
	eq(stim.can_keep("CharacterStateDownedAimFire", true), true)
	eq(stim.can_start("CharacterStateDownedKnockedDown", true), false, "not while knocked about")
	eq(stim.can_start("CharacterStateIdle", true), false, "downed states only")
	stim.allow_downed = false
	eq(stim.can_start("CharacterStateDownedIdle", true), false, "off")
	eq(stim.can_keep("CharacterStateDownedIdle", true), false)
	stim.allow_downed = true
end)

test("the slowdown ends a little before the arm is down, and at once when cut", function()
	local anim = obsidian.module("src/anim")
	eq(stim.slows({ t = 0.2 }), true)
	eq(stim.slows({ t = anim.LENGTH - stim.SLOW_OFF + 0.01 }), false)
	eq(stim.slows({ t = 0.2, cut = 0.2 }), false)
	eq(stim.slows({ t = 0.2 }, "CharacterStateDodge"), false, "a dive keeps its reach")
	eq(stim.slows({ t = 0.2 }, "CharacterStateCrawl"), false, "crawling is slow already")
	eq(stim.slows({ t = 0.2 }, "CharacterStateSprint"), true)
end)

test("the sound starts so its thump lands on the stab", function()
	local anim = obsidian.module("src/anim")
	yes(math.abs(anim.STAB - stim.SOUND_LEAD) < 0.05, "starts with the motion")
end)

test("lying, the arm takes the body's axes; standing, the root's", function()
	local anim = obsidian.module("src/anim")
	local up = { x = 0, y = 0, z = 1 }
	local b = { neck = { x = 0, y = 0, z = 1.8 }, right = { x = 1, y = 0, z = 0 }, fwd = { x = 0, y = 1, z = 0 }, up = up }
	anim.body_axes(b, { x = 0, y = 0.1, z = 1.0 })
	eq(b.up, up, "standing keeps the root")
	local lying = { neck = { x = 0, y = 0.7, z = 0.25 }, right = { x = 1, y = 0, z = 0 }, fwd = { x = 0, y = 1, z = 0 }, up = up }
	anim.body_axes(lying, { x = 0, y = 0, z = 0.2 })
	yes(lying.up.y > 0.95, "up along the spine, toward the head")
	yes(lying.fwd.z < -0.95, "forward is the chest, into the ground")
end)

test("the boost heals 60 a second up to the maximum", function()
	near(stim.heal_step(50, 100, 0.1), 6)
	near(stim.heal_step(97, 100, 0.1), 3)
	eq(stim.heal_step(100, 100, 0.1), 0)
	eq(stim.heal_step(nil, 100, 0.1), 0)
end)

test("another stim can start only once the 4 seconds of the last are over", function()
	eq(stim.refreshed(nil), true, "none yet")
	eq(stim.refreshed(0), false)
	eq(stim.refreshed(3.9), false)
	eq(stim.refreshed(4), true)
end)

test("the screen edge starts strong, weakens over the boost, then fades out", function()
	eq(stim.edge_strength(nil), 0)
	near(stim.edge_strength(stim.EDGE_RISE), 1 - 0.35 * stim.EDGE_RISE / stim.BOOST, 1e-9)
	local early, late = stim.edge_strength(0.5), stim.edge_strength(3.9)
	yes(early > late and late > 0.6, "weaker, still clear near the end")
	near(stim.edge_strength(stim.BOOST), 0.65, 1e-9, "no jump into the fade")
	near(stim.edge_strength(stim.BOOST + stim.EDGE_FADE), 0, 1e-9)
	eq(stim.edge_strength(stim.BOOST + stim.EDGE_FADE + 0.01), 0)
end)

test("the motion: eased raise, even fast stab, a held moment, then straight back", function()
	local anim = obsidian.module("src/anim")
	local w, j = anim.weights(anim.RAISE)
	near(w, 1, 1e-9) near(j, 0, 1e-9, "fist up, not yet in")
	local _, half = anim.weights((anim.RAISE + anim.STAB) / 2)
	near(half, 0.5, 1e-9, "the stab is even")
	w, j = anim.weights((anim.STAB + anim.RELEASE) / 2)
	near(w, 1, 1e-9) near(j, 1, 1e-9, "held in")
	w, j = anim.weights((anim.RELEASE + anim.LENGTH) / 2)
	yes(w > 0 and w < 1, "going back") near(j, 1, 1e-9, "from the stab, not the raised fist")
	yes(anim.STAB - anim.RAISE <= 0.12, "fast")
	yes(anim.RAISE < anim.STAB and anim.STAB < anim.RELEASE and anim.RELEASE < anim.LENGTH)
end)

test("the sounds are plain 16-bit WAVs of one format", function()
	yes(#sounds >= 1)
	local c, r, b = sound.format(sounds[1])
	yes(c == 1 or c == 2, "mono or stereo") eq(b, 16)
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
